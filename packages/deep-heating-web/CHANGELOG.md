# @home-automation/deep-heating-web

## 0.2.3

### Patch Changes

- Updated dependencies [[`6579ec2`](https://github.com/GraemeF/home-automation/commit/6579ec2ef9a557ff81b4d8dcb9479c89e3101dce), [`8a025cd`](https://github.com/GraemeF/home-automation/commit/8a025cd3adba716771d37ae40cf09c1939edf539)]:
  - @home-automation/deep-heating-types@0.3.0

## 0.2.2

### Patch Changes

- [#1295](https://github.com/GraemeF/home-automation/pull/1295) [`3507229`](https://github.com/GraemeF/home-automation/commit/3507229764bd35ee4035ca692d400fdf072dd445) Thanks [@GraemeF](https://github.com/GraemeF)! - Hide incomplete pop-out button behind ENABLE_POPOUT feature flag

- [#1255](https://github.com/GraemeF/home-automation/pull/1255) [`a45e6e1`](https://github.com/GraemeF/home-automation/commit/a45e6e1f64eff52bd8434fff8907383b82d2adc6) Thanks [@GraemeF](https://github.com/GraemeF)! - Add keyed each block for room list to improve Svelte rendering performance

## 0.2.1

### Patch Changes

- Updated dependencies []:
  - @home-automation/deep-heating-types@0.2.1

## 0.2.1-beta.3

### Patch Changes

- Updated dependencies [[`c8db588`](https://github.com/GraemeF/home-automation/commit/c8db588e1ebd50f43e83b39039028bc02c40ff06)]:
  - @home-automation/deep-heating-types@0.2.1-beta.0

## 0.2.1-beta.2

### Patch Changes

- [#1180](https://github.com/GraemeF/home-automation/pull/1180) [`93906a7`](https://github.com/GraemeF/home-automation/commit/93906a7b9966932deabae3f0b597484b8202ef8c) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix UI crash caused by incorrect use of Svelte derived store API - use update() instead of set() with updater functions

## 0.2.1-beta.1

### Patch Changes

- [#1174](https://github.com/GraemeF/home-automation/pull/1174) [`dfe608e`](https://github.com/GraemeF/home-automation/commit/dfe608e5accc49b2d96e8ed74615fe2754497984) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix room temperature sorting by using decodeTemperature helper

## 0.2.1-beta.0

### Patch Changes

- [#1171](https://github.com/GraemeF/home-automation/pull/1171) [`209f367`](https://github.com/GraemeF/home-automation/commit/209f3677a5da613a0a49db801267f48905e0f48e) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix runtime error when receiving WebSocket state updates. The home store was attempting to decode already-decoded state data, causing "Cannot read properties of undefined (reading '\_tag')" errors on Option fields.

## 0.2.0

### Minor Changes

- [#1148](https://github.com/GraemeF/home-automation/pull/1148) [`6b93928`](https://github.com/GraemeF/home-automation/commit/6b939286d0c17d4b5f8efa74525a6c03f9da811d) Thanks [@GraemeF](https://github.com/GraemeF)! - Upgrade to Svelte 5 and Vite 6 with latest SvelteKit

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
