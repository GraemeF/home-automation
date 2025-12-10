---
'@home-automation/deep-heating-rx': patch
---

Fix TRV scheduled target temperatures to emit for all TRVs when timer fires, not just the last one. Previously only one TRV would receive scheduled temperature updates, blocking heating actions for other rooms.
