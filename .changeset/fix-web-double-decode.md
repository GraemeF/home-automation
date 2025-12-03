---
'@home-automation/deep-heating-web': patch
---

Fix runtime error when receiving WebSocket state updates. The home store was attempting to decode already-decoded state data, causing "Cannot read properties of undefined (reading '\_tag')" errors on Option fields.
