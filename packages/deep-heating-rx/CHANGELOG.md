# @home-automation/deep-heating-rx

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
