---
'deep-heating-socketio': minor
---

Add graceful shutdown support. The server now properly handles restart and shutdown signals, cleaning up resources without leaving orphaned connections.
