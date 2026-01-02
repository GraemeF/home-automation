---
'@home-automation/deep-heating-home-assistant': minor
---

Add HomeAssistantHeatingSystemLive Layer for Home Assistant integration

New exports:

- `HomeAssistantHeatingSystemLive` - Effect Layer that provides HeatingSystem service using Home Assistant as the backend
- Manages entity polling lifecycle with proper resource cleanup
- Wires TRV updates, heating updates, temperature readings, and sleep mode events from Home Assistant
