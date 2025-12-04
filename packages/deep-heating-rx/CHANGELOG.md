# @home-automation/deep-heating-rx

## 0.1.3-beta.3

### Patch Changes

- [#1192](https://github.com/GraemeF/home-automation/pull/1192) [`1197dbc`](https://github.com/GraemeF/home-automation/commit/1197dbc465e5ef26d0eb5573f0f3ef6520d40903) Thanks [@GraemeF](https://github.com/GraemeF)! - Remove broken 60-second timer from TRV desired target temperature calculation. The timer only recalculated the last TRV that emitted, not all TRVs - a bug that existed since the original implementation when there was only one TRV per room.

## 0.1.3-beta.2

### Patch Changes

- [#1190](https://github.com/GraemeF/home-automation/pull/1190) [`2cc324b`](https://github.com/GraemeF/home-automation/commit/2cc324b4e80f6f4958bc823c7642d156bd6ccb0b) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix TRV control state updates being suppressed when device returns from unavailable

  When a TRV goes unavailable and comes back online, the device may report a stale
  target temperature that differs from what the system last commanded. Previously,
  if the device reported the same mode and temperature as our cached synthesised
  command, the device update would be suppressed and no corrective action would be
  generated.

  Now, device updates are always emitted if the source differs from the cached
  value (Device vs Synthesised), ensuring the action pipeline can re-evaluate and
  push the correct temperature to the TRV.

## 0.1.3-beta.1

### Patch Changes

- [#1185](https://github.com/GraemeF/home-automation/pull/1185) [`896b6ae`](https://github.com/GraemeF/home-automation/commit/896b6ae80cc81829d06015a9b907dcdf6ca4d8e9) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix TRV control states not replaying to late subscribers

  The `trvControlStates$` stream was using `share()` at the end of its pipeline,
  which doesn't replay values to new subscribers. This caused downstream
  `combineLatest` chains to never fire for TRVs that didn't receive continuous
  updates - only the Office radiator was being controlled while all other rooms
  remained cold.

  Changed to use `shareReplayLatestDistinctByKey` which maintains a map of the
  latest value per TRV and replays all known values to new subscribers.

## 0.1.3-beta.0

### Patch Changes

- [#1182](https://github.com/GraemeF/home-automation/pull/1182) [`9aed2df`](https://github.com/GraemeF/home-automation/commit/9aed2dfe12ccd16404201a348cbf911a6dc469f6) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix TRV scheduled temperatures not replaying for all radiators

  The `getTrvScheduledTargetTemperatures` function was using `combineLatest` which
  only stores the latest value from each input stream. When the 60-second timer
  fired, it only re-emitted for the last TRV to have updated (typically Office),
  causing other radiators to stop receiving target temperature updates.

  Added `shareReplayLatestDistinctByKey` to properly store and replay each TRV's
  scheduled target temperature independently.

## 0.1.2

### Patch Changes

- Updated dependencies [[`545a2ac`](https://github.com/GraemeF/home-automation/commit/545a2acb0a8ba1b5065df6f25130bf1472330e5f)]:
  - @home-automation/deep-heating-types@0.2.0
  - @home-automation/deep-heating-home-assistant@0.1.2

## 0.1.1

### Patch Changes

- Updated dependencies [[`b65e00e`](https://github.com/GraemeF/home-automation/commit/b65e00e577d409d6f61173d514dcd6aed3863c7f)]:
  - @home-automation/deep-heating-types@0.1.1
  - @home-automation/deep-heating-home-assistant@0.1.1

## 0.1.0

### Minor Changes

- [#1122](https://github.com/GraemeF/home-automation/pull/1122) [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e) Thanks [@GraemeF](https://github.com/GraemeF)! - Internal improvements: migrate core systems to Effect, upgrade RxJS to v7, modernise TypeScript configuration, and improve build tooling

### Patch Changes

- Updated dependencies [[`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e), [`d7e0cca`](https://github.com/GraemeF/home-automation/commit/d7e0cca9c9d0bc6009a926382d43b4cbb4082d12)]:
  - @home-automation/deep-heating-home-assistant@0.1.0
  - @home-automation/deep-heating-types@0.1.0
  - @home-automation/rxx@0.1.0
