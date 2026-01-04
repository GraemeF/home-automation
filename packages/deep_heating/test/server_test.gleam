import deep_heating/server
import gleam/string
import gleeunit/should

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

pub fn html_page_contains_tailwind_test() {
  let html = server.render_html_page()
  html
  |> string.contains("tailwindcss.com")
  |> should.be_true
}

pub fn html_page_contains_daisyui_test() {
  let html = server.render_html_page()
  html
  |> string.contains("daisyui")
  |> should.be_true
}

pub fn html_page_contains_title_test() {
  let html = server.render_html_page()
  html
  |> string.contains("Deep Heating")
  |> should.be_true
}
