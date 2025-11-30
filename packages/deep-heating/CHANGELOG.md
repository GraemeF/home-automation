# @home-automation/deep-heating

## 0.0.9

### Patch Changes

- Updated dependencies [[`d92bd4e`](https://github.com/GraemeF/home-automation/commit/d92bd4ef37126aeaa16f3e1c63d6796f67919496)]:
  - @home-automation/deep-heating-web@0.0.3

## 0.0.8

### Patch Changes

- [#1128](https://github.com/GraemeF/home-automation/pull/1128) [`a3a54a0`](https://github.com/GraemeF/home-automation/commit/a3a54a0ba6360947a680f9f5186718be9b8b30f0) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix Home Assistant add-on ingress 502 error and follow HA best practices
  - Switch to HA default ingress port 8099 (was using non-standard 8503)
  - Add `init: false` for s6 custom init system
  - Enable `deny all` in nginx to only accept ingress proxy connections

## 0.0.7

### Patch Changes

- Updated dependencies []:
  - deep-heating-socketio@0.1.1

## 0.0.6

### Patch Changes

- [#1122](https://github.com/GraemeF/home-automation/pull/1122) [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e) Thanks [@GraemeF](https://github.com/GraemeF)! - Internal improvements: migrate core systems to Effect, upgrade RxJS to v7, modernise TypeScript configuration, and improve build tooling

- Updated dependencies [[`95b76f4`](https://github.com/GraemeF/home-automation/commit/95b76f4daeaca9fab8f252487769b8a344d6e80a), [`682c648`](https://github.com/GraemeF/home-automation/commit/682c64824eff90b155f06f1c13d7ee0fb396e79e)]:
  - deep-heating-socketio@0.1.0
  - @home-automation/deep-heating-web@0.0.2

## 0.0.5

### Patch Changes

- [#1069](https://github.com/GraemeF/home-automation/pull/1069) [`4edf11f`](https://github.com/GraemeF/home-automation/commit/4edf11fe43e50a13b8fff7862fc10b325b05f03f) Thanks [@GraemeF](https://github.com/GraemeF)! - Fix Docker image path in Home Assistant addon config

## 0.0.4

### Patch Changes

- [#1061](https://github.com/GraemeF/home-automation/pull/1061) [`cca2604`](https://github.com/GraemeF/home-automation/commit/cca2604d1dfb2df3b64088a0182a3ddda853cfdd) Thanks [@GraemeF](https://github.com/GraemeF)! - Add GitHub releases to release workflow with changelog and Docker image links

## 0.0.3

### Patch Changes

- [#1053](https://github.com/GraemeF/home-automation/pull/1053) [`734ea94`](https://github.com/GraemeF/home-automation/commit/734ea946f4702785d3b4fa8af17db93669ea6c53) Thanks [@GraemeF](https://github.com/GraemeF)! - Remove unsupported armhf and armv7 architectures from config.yaml - we only build for amd64 and aarch64

## 0.0.2

### Patch Changes

- [#1045](https://github.com/GraemeF/home-automation/pull/1045) [`1be0a97`](https://github.com/GraemeF/home-automation/commit/1be0a97dac631a1f043f8ef7b2ef4e427a3bcc37) Thanks [@GraemeF](https://github.com/GraemeF)! - Test Docker build integration with release workflow
