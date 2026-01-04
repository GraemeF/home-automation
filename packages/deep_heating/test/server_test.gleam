import deep_heating/server
import envoy
import gleam/string
import gleeunit/should

// Test port configuration from environment

pub fn port_from_env_returns_default_when_not_set_test() {
  // Ensure PORT is not set
  envoy.unset("PORT")

  server.port_from_env()
  |> should.equal(server.default_port)
}

pub fn port_from_env_returns_env_value_when_set_test() {
  envoy.set("PORT", "9999")

  server.port_from_env()
  |> should.equal(9999)

  // Clean up
  envoy.unset("PORT")
}

pub fn port_from_env_returns_default_when_invalid_test() {
  envoy.set("PORT", "not_a_number")

  server.port_from_env()
  |> should.equal(server.default_port)

  // Clean up
  envoy.unset("PORT")
}

// Test that the HTML page has required elements
pub fn html_page_contains_server_component_test() {
  let html = server.render_html_page()
  html
  |> string.contains("lustre-server-component")
  |> should.be_true
}

pub fn html_page_contains_ws_route_test() {
  let html = server.render_html_page()
  html
  |> string.contains("/ws")
  |> should.be_true
}

pub fn html_page_contains_lustre_runtime_script_test() {
  let html = server.render_html_page()
  html
  |> string.contains("/lustre/runtime.mjs")
  |> should.be_true
}

pub fn html_page_contains_styles_test() {
  let html = server.render_html_page()
  // Tailwind + DaisyUI compiled CSS is bundled locally for offline HA addon support
  html
  |> string.contains("/static/styles.css")
  |> should.be_true
}

pub fn html_page_contains_title_test() {
  let html = server.render_html_page()
  html
  |> string.contains("Deep Heating")
  |> should.be_true
}
