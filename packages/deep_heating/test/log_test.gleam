import deep_heating/log.{level_from_string}
import gleeunit/should
import logging

// level_from_string tests

pub fn level_from_string_debug_test() {
  level_from_string("debug") |> should.equal(Ok(logging.Debug))
}

pub fn level_from_string_debug_uppercase_test() {
  level_from_string("DEBUG") |> should.equal(Ok(logging.Debug))
}

pub fn level_from_string_info_test() {
  level_from_string("info") |> should.equal(Ok(logging.Info))
}

pub fn level_from_string_warning_test() {
  level_from_string("warning") |> should.equal(Ok(logging.Warning))
}

pub fn level_from_string_error_test() {
  level_from_string("error") |> should.equal(Ok(logging.Error))
}

pub fn level_from_string_notice_test() {
  level_from_string("notice") |> should.equal(Ok(logging.Notice))
}

pub fn level_from_string_alert_test() {
  level_from_string("alert") |> should.equal(Ok(logging.Alert))
}

pub fn level_from_string_critical_test() {
  level_from_string("critical") |> should.equal(Ok(logging.Critical))
}

pub fn level_from_string_emergency_test() {
  level_from_string("emergency") |> should.equal(Ok(logging.Emergency))
}

pub fn level_from_string_invalid_test() {
  level_from_string("banana") |> should.be_error
}

pub fn level_from_string_empty_test() {
  level_from_string("") |> should.be_error
}
