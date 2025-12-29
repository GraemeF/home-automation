---
'@home-automation/deep-heating-types': minor
---

Add HeatingSystem Effect Service for abstracting device communication

New exports:

- `HeatingSystem` Effect Service (Context.Tag) with Observable streams for TRV updates, heating updates, temperature readings, and sleep mode events
- Effect-based `setTrvTemperature` and `setTrvMode` actions
- `HeatingSystemError` type for typed error handling
- Can be provided via Layer for dependency injection
