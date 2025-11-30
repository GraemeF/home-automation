---
'deep-heating-socketio': minor
---

Add graceful shutdown support using Effect's BunRuntime.runMain. The server now properly handles SIGINT/SIGTERM signals and cleans up resources on shutdown.
