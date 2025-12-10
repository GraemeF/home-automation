# @home-automation/deep-heating-state

## 0.1.4-beta.7

### Patch Changes

- Updated dependencies [[`e9453cb`](https://github.com/GraemeF/home-automation/commit/e9453cb8a30816cacf57ece62cf90c93f2f7f9a2)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.7

## 0.1.4-beta.6

### Patch Changes

- Updated dependencies []:
  - @home-automation/deep-heating-rx@0.1.3-beta.6

## 0.1.4-beta.5

### Patch Changes

- Updated dependencies [[`0b0c129`](https://github.com/GraemeF/home-automation/commit/0b0c1290426220ee7f1f4af697052de3126524cb)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.5

## 0.1.4-beta.4

### Patch Changes

- Updated dependencies [[`c8db588`](https://github.com/GraemeF/home-automation/commit/c8db588e1ebd50f43e83b39039028bc02c40ff06)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.4
  - @home-automation/deep-heating-types@0.2.1-beta.0

## 0.1.4-beta.3

### Patch Changes

- Updated dependencies [[`1197dbc`](https://github.com/GraemeF/home-automation/commit/1197dbc465e5ef26d0eb5573f0f3ef6520d40903)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.3

## 0.1.4-beta.2

### Patch Changes

- Updated dependencies [[`2cc324b`](https://github.com/GraemeF/home-automation/commit/2cc324b4e80f6f4958bc823c7642d156bd6ccb0b)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.2

## 0.1.4-beta.1

### Patch Changes

- Updated dependencies [[`896b6ae`](https://github.com/GraemeF/home-automation/commit/896b6ae80cc81829d06015a9b907dcdf6ca4d8e9)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.1

## 0.1.4-beta.0

### Patch Changes

- Updated dependencies [[`9aed2df`](https://github.com/GraemeF/home-automation/commit/9aed2dfe12ccd16404201a348cbf911a6dc469f6)]:
  - @home-automation/deep-heating-rx@0.1.3-beta.0

## 0.1.3

### Patch Changes

- Updated dependencies [[`545a2ac`](https://github.com/GraemeF/home-automation/commit/545a2acb0a8ba1b5065df6f25130bf1472330e5f)]:
  - @home-automation/deep-heating-types@0.2.0
  - @home-automation/deep-heating-rx@0.1.2

## 0.1.2

### Patch Changes

- Updated dependencies [[`b65e00e`](https://github.com/GraemeF/home-automation/commit/b65e00e577d409d6f61173d514dcd6aed3863c7f)]:
  - @home-automation/deep-heating-types@0.1.1
  - @home-automation/deep-heating-rx@0.1.1

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
