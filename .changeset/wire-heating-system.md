---
'@home-automation/deep-heating-rx': minor
'deep-heating-server': patch
---

Add HeatingSystemStreams interface for decoupled heating system integration

The reactive heating logic now accepts an abstract HeatingSystemStreams interface instead of concrete Home Assistant dependencies. This enables easier testing and future alternative heating system implementations.
