---
'@home-automation/deep-heating-rx': patch
---

Fix startup race condition where TRV actions could be silently dropped if emitted before control state streams were ready
