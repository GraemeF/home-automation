---
'@home-automation/deep-heating-rx': patch
---

Fix TRV scheduled temperatures not replaying for all radiators

The `getTrvScheduledTargetTemperatures` function was using `combineLatest` which
only stores the latest value from each input stream. When the 60-second timer
fired, it only re-emitted for the last TRV to have updated (typically Office),
causing other radiators to stop receiving target temperature updates.

Added `shareReplayLatestDistinctByKey` to properly store and replay each TRV's
scheduled target temperature independently.
