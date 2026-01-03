import gleeunit
import test_helpers

pub fn main() -> Nil {
  // Silence OTP logs (CRASH REPORT, SUPERVISOR REPORT, etc.) during tests
  let _level = test_helpers.silence_otp_logs()
  gleeunit.main()
}
