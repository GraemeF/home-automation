# @home-automation/deep-heating-state

## 0.1.1

### Patch Changes

- [#1125](https://github.com/GraemeF/home-automation/pull/1125) [`c708880`](https://github.com/GraemeF/home-automation/commit/c7088808c02876d6a6a849fcd176fc356321407e) Thanks [@GraemeF](https://github.com/GraemeF)! - Remove rxjs-multi-scan dependency and replace with native RxJS 7 operators

  The rxjs-multi-scan package (unmaintained since 2018) required RxJS 6.x, causing type
  incompatibilities in Nix Docker builds after the RxJS 7 upgrade. Replaced multiScan
  calls with merge + scan pattern using native RxJS 7 operators.

## 0.1.0

### Minor Changes

- [#1122](https://github.com/GraemeF/home-automation/pull/1122) [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e) Thanks [@GraemeF](https://github.com/GraemeF)! - Internal improvements: migrate core systems to Effect, upgrade RxJS to v7, modernise TypeScript configuration, and improve build tooling

### Patch Changes

- Updated dependencies [[`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e)]:
  - @home-automation/deep-heating-rx@0.1.0
  - @home-automation/deep-heating-types@0.1.0
