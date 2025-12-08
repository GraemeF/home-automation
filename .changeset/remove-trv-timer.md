---
'@home-automation/deep-heating-rx': patch
---

Remove broken 60-second timer from TRV desired target temperature calculation. The timer only recalculated the last TRV that emitted, not all TRVs - a bug that existed since the original implementation when there was only one TRV per room.
