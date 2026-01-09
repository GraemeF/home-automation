import deep_heating/log
import gleeunit/should
import logging

// level_from_string tests

pub fn level_from_string_debug_test() {
  log.level_from_string("debug") |> should.equal(Ok(logging.Debug))
}

pub fn level_from_string_debug_uppercase_test() {
  log.level_from_string("DEBUG") |> should.equal(Ok(logging.Debug))
}

pub fn level_from_string_info_test() {
  log.level_from_string("info") |> should.equal(Ok(logging.Info))
}

pub fn level_from_string_warning_test() {
  log.level_from_string("warning") |> should.equal(Ok(logging.Warning))
}

pub fn level_from_string_error_test() {
  log.level_from_string("error") |> should.equal(Ok(logging.Error))
}

pub fn level_from_string_notice_test() {
  log.level_from_string("notice") |> should.equal(Ok(logging.Notice))
}

pub fn level_from_string_alert_test() {
  log.level_from_string("alert") |> should.equal(Ok(logging.Alert))
}

pub fn level_from_string_critical_test() {
  log.level_from_string("critical") |> should.equal(Ok(logging.Critical))
}

pub fn level_from_string_emergency_test() {
  log.level_from_string("emergency") |> should.equal(Ok(logging.Emergency))
}

pub fn level_from_string_invalid_test() {
  log.level_from_string("banana") |> should.be_error
}

pub fn level_from_string_empty_test() {
  log.level_from_string("") |> should.be_error
}

// format_actor tests

pub fn format_actor_prefixes_with_actor_name_test() {
  log.format_actor("HaPoller", "Polling started")
  |> should.equal("[HaPoller] Polling started")
}

pub fn format_actor_handles_empty_message_test() {
  log.format_actor("RoomDecision", "")
  |> should.equal("[RoomDecision] ")
}

// format_entity tests

pub fn format_entity_prefixes_with_entity_id_test() {
  log.format_entity("climate.bedroom", "Target updated to 21°C")
  |> should.equal("[climate.bedroom] Target updated to 21°C")
}

pub fn format_entity_handles_empty_message_test() {
  log.format_entity("sensor.kitchen", "")
  |> should.equal("[sensor.kitchen] ")
}

// state_change tests - for logging transitions like "heat→off"

pub fn state_change_formats_from_to_test() {
  log.state_change("heat", "off")
  |> should.equal("heat→off")
}

pub fn state_change_with_temperatures_test() {
  log.state_change("19.5", "21.0")
  |> should.equal("19.5→21.0")
}

// Convenience logging functions - smoke tests (no assertions, just verify they don't crash)

pub fn actor_debug_does_not_crash_test() {
  log.actor_debug("TestActor", "debug message")
  Nil |> should.equal(Nil)
}

pub fn actor_info_does_not_crash_test() {
  log.actor_info("TestActor", "info message")
  Nil |> should.equal(Nil)
}

pub fn actor_warning_does_not_crash_test() {
  log.actor_warning("TestActor", "warning message")
  Nil |> should.equal(Nil)
}

pub fn actor_error_does_not_crash_test() {
  log.actor_error("TestActor", "error message")
  Nil |> should.equal(Nil)
}

pub fn entity_debug_does_not_crash_test() {
  log.entity_debug("climate.test", "debug message")
  Nil |> should.equal(Nil)
}

pub fn entity_info_does_not_crash_test() {
  log.entity_info("climate.test", "info message")
  Nil |> should.equal(Nil)
}

pub fn entity_warning_does_not_crash_test() {
  log.entity_warning("climate.test", "warning message")
  Nil |> should.equal(Nil)
}

pub fn entity_error_does_not_crash_test() {
  log.entity_error("climate.test", "error message")
  Nil |> should.equal(Nil)
}
