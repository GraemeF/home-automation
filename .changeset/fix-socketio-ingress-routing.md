---
'@home-automation/deep-heating-web': patch
---

Fix Socket.IO connection when running behind Home Assistant ingress proxy. Socket.IO requests now correctly route through the ingress path instead of hitting the main HA port directly.
