---
'@home-automation/deep-heating': patch
---

Fix Home Assistant add-on ingress 502 error and follow HA best practices

- Switch to HA default ingress port 8099 (was using non-standard 8503)
- Add `init: false` for s6 custom init system
- Enable `deny all` in nginx to only accept ingress proxy connections
