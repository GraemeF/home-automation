---
'@home-automation/deep-heating': patch
'@home-automation/deep-heating-home-assistant': patch
'@home-automation/deep-heating-rx': patch
'@home-automation/deep-heating-state': patch
'@home-automation/deep-heating-types': patch
'@home-automation/deep-heating-web': patch
'@home-automation/rxx': patch
'deep-heating-socketio': patch
'dictionary': patch
---

Modernise TypeScript configuration

- Update target from ES2015 to ES2022
- Switch moduleResolution from node to bundler
- Update lib from es2017 to es2022
- Add Effect language service plugin for better IDE support
- Update all package tsconfigs from commonjs to esnext module
