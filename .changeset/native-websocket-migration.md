---
'@home-automation/deep-heating-types': minor
'@home-automation/deep-heating-web': minor
'@home-automation/deep-heating': minor
---

Replace Socket.IO with native WebSocket for real-time communication

- Server now uses Bun's native WebSocket API with Effect patterns for connection management
- Client uses browser's native WebSocket with exponential backoff reconnection
- New WebSocket message schemas for type-safe client-server communication
- Removes Socket.IO dependency, reducing bundle size and complexity
