# @home-automation/deep-heating-web

## 0.1.0

### Minor Changes

- [#1140](https://github.com/GraemeF/home-automation/pull/1140) [`545a2ac`](https://github.com/GraemeF/home-automation/commit/545a2acb0a8ba1b5065df6f25130bf1472330e5f) Thanks [@GraemeF](https://github.com/GraemeF)! - Replace Socket.IO with native WebSocket for real-time communication
  - Server now uses Bun's native WebSocket API with Effect patterns for connection management
  - Client uses browser's native WebSocket with exponential backoff reconnection
  - New WebSocket message schemas for type-safe client-server communication
  - Removes Socket.IO dependency, reducing bundle size and complexity

### Patch Changes

- Updated dependencies [[`545a2ac`](https://github.com/GraemeF/home-automation/commit/545a2acb0a8ba1b5065df6f25130bf1472330e5f)]:
  - @home-automation/deep-heating-types@0.2.0

## 0.0.4

### Patch Changes

- Updated dependencies [[`b65e00e`](https://github.com/GraemeF/home-automation/commit/b65e00e577d409d6f61173d514dcd6aed3863c7f)]:
  - @home-automation/deep-heating-types@0.1.1

## 0.0.3

### Patch Changes

- [#1132](https://github.com/GraemeF/home-automation/pull/1132) [`d92bd4e`](https://github.com/GraemeF/home-automation/commit/d92bd4ef37126aeaa16f3e1c63d6796f67919496) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix Socket.IO connection when running behind Home Assistant ingress proxy. Socket.IO requests now correctly route through the ingress path instead of hitting the main HA port directly.

## 0.0.2

### Patch Changes

- [#1122](https://github.com/GraemeF/home-automation/pull/1122) [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e) Thanks [@GraemeF](https://github.com/GraemeF)! - Internal improvements: migrate core systems to Effect, upgrade RxJS to v7, modernise TypeScript configuration, and improve build tooling

- Updated dependencies [[`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e)]:
  - @home-automation/deep-heating-types@0.1.0
