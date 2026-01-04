//// Server module - HTTP/WebSocket server for Lustre server components.
////
//// This module provides:
//// - HTTP server for serving the HTML and JavaScript client runtime
//// - WebSocket endpoint for Lustre server component communication
//// - Integration with StateAggregatorActor for real-time state updates

import deep_heating/actor/state_aggregator_actor
import deep_heating/state.{type DeepHeatingState}
import deep_heating/ui/app
import deep_heating/ui/msg.{type Msg, Connected, Disconnected, StateReceived}
import deep_heating/ui/update
import envoy
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}

/// Default port for the server (aligns with existing TS backend)
pub const default_port: Int = 8085

/// Default host for the server
pub const default_host: String = "0.0.0.0"

/// Get the port from PORT environment variable, or default_port if not set/invalid.
pub fn port_from_env() -> Int {
  case envoy.get("PORT") {
    Ok(port_str) ->
      case int.parse(port_str) {
        Ok(port) -> port
        Error(_) -> default_port
      }
    Error(_) -> default_port
  }
}

/// Configuration for the server
pub type ServerConfig {
  ServerConfig(
    /// The port to listen on (default: 8085)
    port: Int,
    /// The host to bind to (default: "0.0.0.0")
    host: String,
    /// Subject to the StateAggregatorActor for subscribing to state updates
    state_aggregator: Subject(state_aggregator_actor.Message),
    /// Callback to send room adjustments (room_name, adjustment)
    room_adjuster: fn(String, Float) -> Nil,
  )
}

/// Create a server config with default port and host
pub fn default_config(
  state_aggregator: Subject(state_aggregator_actor.Message),
  room_adjuster: fn(String, Float) -> Nil,
) -> ServerConfig {
  ServerConfig(
    port: default_port,
    host: default_host,
    state_aggregator:,
    room_adjuster:,
  )
}

/// Start the HTTP/WebSocket server.
pub fn start(config: ServerConfig) -> Result(Nil, String) {
  let handler = fn(request: Request(Connection)) -> Response(ResponseData) {
    case request.path_segments(request) {
      // Serve the main HTML page
      [] -> serve_html()
      // Serve the Lustre client runtime
      ["lustre", "runtime.mjs"] -> serve_runtime()
      // WebSocket endpoint for server component communication
      ["ws"] -> serve_websocket(request, config)
      // 404 for everything else
      _ -> response.set_body(response.new(404), mist.Bytes(bytes_tree.new()))
    }
  }

  mist.new(handler)
  |> mist.bind(config.host)
  |> mist.port(config.port)
  |> mist.start
  |> result_to_string_error
}

fn result_to_string_error(result: Result(a, b)) -> Result(Nil, String) {
  case result {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error(string.inspect(e))
  }
}

// HTML ------------------------------------------------------------------------

/// Render the HTML page as a string.
/// This is the main HTML document served to browsers.
pub fn render_html_page() -> String {
  html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Deep Heating"),
      // Include Tailwind CSS for styling (using CDN for development)
      html.link([
        attribute.rel("stylesheet"),
        attribute.href(
          "https://cdn.jsdelivr.net/npm/daisyui@4.4.19/dist/full.min.css",
        ),
      ]),
      html.script([attribute.src("https://cdn.tailwindcss.com")], ""),
      // Include the Lustre server component runtime
      html.script(
        [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
        "",
      ),
    ]),
    html.body([attribute.class("bg-base-200 min-h-screen")], [
      // The Lustre server component element connects to /ws
      server_component.element([server_component.route("/ws")], []),
    ]),
  ])
  |> element.to_document_string
}

fn serve_html() -> Response(ResponseData) {
  let html_content =
    render_html_page()
    |> bytes_tree.from_string

  response.new(200)
  |> response.set_body(mist.Bytes(html_content))
  |> response.set_header("content-type", "text/html")
}

// JavaScript Runtime ----------------------------------------------------------

fn serve_runtime() -> Response(ResponseData) {
  // Serve the Lustre server component client runtime
  let assert Ok(lustre_priv) = application.priv_directory("lustre")
  let file_path = lustre_priv <> "/static/lustre-server-component.mjs"

  case mist.send_file(file_path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", "application/javascript")
      |> response.set_body(file)

    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

// WebSocket Handler -----------------------------------------------------------

/// State maintained for each WebSocket connection
type SocketState {
  SocketState(
    /// The Lustre runtime for this connection
    runtime: lustre.Runtime(Msg),
    /// Our subject for receiving messages from the runtime
    self: Subject(server_component.ClientMessage(Msg)),
    /// Subject to receive state updates from the aggregator
    state_subject: Subject(DeepHeatingState),
    /// Reference to the state aggregator for cleanup
    state_aggregator: Subject(state_aggregator_actor.Message),
  )
}

type SocketMessage {
  /// Message from the Lustre runtime to send to client
  RuntimeMessage(server_component.ClientMessage(Msg))
  /// State update from the StateAggregatorActor
  StateUpdate(DeepHeatingState)
}

type SocketInit =
  #(SocketState, Option(Selector(SocketMessage)))

fn serve_websocket(
  request: Request(Connection),
  config: ServerConfig,
) -> Response(ResponseData) {
  mist.websocket(
    request:,
    on_init: fn(_conn) { init_socket(config) },
    handler: loop_socket,
    on_close: close_socket,
  )
}

fn init_socket(config: ServerConfig) -> SocketInit {
  // Create dependencies for the update function
  let deps = update.Dependencies(adjust_room: config.room_adjuster)

  // Create the Lustre app with dependencies
  let lustre_app = app.app(deps)

  // Start the server component runtime
  let assert Ok(runtime) = lustre.start_server_component(lustre_app, Nil)

  // Create subject for receiving messages from the Lustre runtime
  let self = process.new_subject()

  // Create subject for receiving state updates from the aggregator
  let state_subject = process.new_subject()

  // Set up selector to receive both types of messages
  let selector =
    process.new_selector()
    |> process.select_map(self, RuntimeMessage)
    |> process.select_map(state_subject, StateUpdate)

  // Register our subject with the Lustre runtime
  server_component.register_subject(self)
  |> lustre.send(to: runtime)

  // Subscribe to state updates from the aggregator
  process.send(
    config.state_aggregator,
    state_aggregator_actor.Subscribe(state_subject),
  )

  // Send connected message to the runtime
  lustre.dispatch(Connected)
  |> lustre.send(to: runtime)

  let state =
    SocketState(
      runtime:,
      self:,
      state_subject:,
      state_aggregator: config.state_aggregator,
    )

  #(state, Some(selector))
}

fn loop_socket(
  state: SocketState,
  message: mist.WebsocketMessage(SocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(SocketState, SocketMessage) {
  case message {
    // Handle incoming JSON messages from the client runtime
    mist.Text(json_text) -> {
      case json.parse(json_text, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.runtime, runtime_message)
        Error(_) -> Nil
      }
      mist.continue(state)
    }

    mist.Binary(_) -> {
      mist.continue(state)
    }

    // Handle messages that need to be forwarded
    mist.Custom(socket_message) -> {
      case socket_message {
        // Forward Lustre runtime messages to the client
        RuntimeMessage(client_message) -> {
          let json_msg = server_component.client_message_to_json(client_message)
          let _ = mist.send_text_frame(connection, json.to_string(json_msg))
          Nil
        }
        // Dispatch state updates to the Lustre runtime
        StateUpdate(deep_state) -> {
          lustre.dispatch(StateReceived(deep_state))
          |> lustre.send(to: state.runtime)
        }
      }
      mist.continue(state)
    }

    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn close_socket(state: SocketState) -> Nil {
  // Send disconnected message before shutting down
  lustre.dispatch(Disconnected)
  |> lustre.send(to: state.runtime)

  // Unsubscribe from state updates
  process.send(
    state.state_aggregator,
    state_aggregator_actor.Unsubscribe(state.state_subject),
  )

  // Shut down the Lustre runtime
  lustre.shutdown()
  |> lustre.send(to: state.runtime)
}
