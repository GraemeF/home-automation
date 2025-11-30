---
'@home-automation/deep-heating-home-assistant': patch
---

Add typed error handling with Effect.catchTag for Home Assistant API operations. Errors now include HomeAssistantConnectionError, SetTemperatureError, and SetHvacModeError with detailed context for debugging.
