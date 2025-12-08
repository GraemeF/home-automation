---
'@home-automation/deep-heating-home-assistant': patch
---

Improve resilience of Home Assistant entity parsing by using Effect-based decoding instead of synchronous decoding, enabling proper error handling and retry logic when malformed entity data is received
