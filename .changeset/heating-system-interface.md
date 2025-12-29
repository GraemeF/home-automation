---
'@home-automation/deep-heating-types': minor
---

Add HeatingSystem interface for abstracting device communication

New exports:

- `HeatingSystem` interface with Observable streams for TRV updates, heating updates, temperature readings, and sleep mode events
- Effect-based `setTrvTemperature` and `setTrvMode` actions
- `HeatingSystemError` type for typed error handling
