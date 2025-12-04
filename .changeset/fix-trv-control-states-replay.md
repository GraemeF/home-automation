---
'@home-automation/deep-heating-rx': patch
---

Fix TRV control states not replaying to late subscribers

The `trvControlStates$` stream was using `share()` at the end of its pipeline,
which doesn't replay values to new subscribers. This caused downstream
`combineLatest` chains to never fire for TRVs that didn't receive continuous
updates - only the Office radiator was being controlled while all other rooms
remained cold.

Changed to use `shareReplayLatestDistinctByKey` which maintains a map of the
latest value per TRV and replays all known values to new subscribers.
