# @home-automation/deep-heating-types

## 0.2.1-beta.0

### Patch Changes

- [#1194](https://github.com/GraemeF/home-automation/pull/1194) [`c8db588`](https://github.com/GraemeF/home-automation/commit/c8db588e1ebd50f43e83b39039028bc02c40ff06) Thanks [@GraemeF](https://github.com/GraemeF)! - Add debug logging for scheduled target temperatures and test for Wednesday evening schedule behavior

## 0.2.0

### Minor Changes

- [#1140](https://github.com/GraemeF/home-automation/pull/1140) [`545a2ac`](https://github.com/GraemeF/home-automation/commit/545a2acb0a8ba1b5065df6f25130bf1472330e5f) Thanks [@GraemeF](https://github.com/GraemeF)! - Replace Socket.IO with native WebSocket for real-time communication
  - Server now uses Bun's native WebSocket API with Effect patterns for connection management
  - Client uses browser's native WebSocket with exponential backoff reconnection
  - New WebSocket message schemas for type-safe client-server communication
  - Removes Socket.IO dependency, reducing bundle size and complexity

## 0.1.1

### Patch Changes

- [#1137](https://github.com/GraemeF/home-automation/pull/1137) [`b65e00e`](https://github.com/GraemeF/home-automation/commit/b65e00e577d409d6f61173d514dcd6aed3863c7f) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix Socket.IO state encoding to properly serialize Effect Option types for client consumption

## 0.1.0

### Minor Changes

- [#1122](https://github.com/GraemeF/home-automation/pull/1122) [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e) Thanks [@GraemeF](https://github.com/GraemeF)! - Internal improvements: migrate core systems to Effect, upgrade RxJS to v7, modernise TypeScript configuration, and improve build tooling

## 0.0.3

### Patch Changes

- [#1049](https://github.com/GraemeF/home-automation/pull/1049) [`71543e5`](https://github.com/GraemeF/home-automation/commit/71543e58438c6992da1362c26779ebaf9024925b) Thanks [@GraemeF](https://github.com/GraemeF)! - Add package description to deep-heating-types

## 0.0.2

### Patch Changes

- [#1040](https://github.com/GraemeF/home-automation/pull/1040) [`55b0121`](https://github.com/GraemeF/home-automation/commit/55b0121dc2628b5f8f817d0f8befaf8b76566006) Thanks [@GraemeF](https://github.com/GraemeF)! - Test changeset to verify release workflow
