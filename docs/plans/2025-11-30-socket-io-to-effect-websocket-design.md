# Replace Socket.IO with Effect Platform WebSocket

**Issue:** dh-mdh
**Date:** 2025-11-30
**Status:** Design Complete

## Overview

Replace Socket.IO with Effect Platform's WebSocket server for real-time client-server communication. This aligns the WebSocket layer with the broader Effect architecture migration.

## Goals

- Unified Effect architecture throughout the server
- Type-safe message protocol with Schema validation
- Proper Effect lifecycle management (Scope, Layers)
- Remove Socket.IO dependency and complexity

## Non-Goals

- Effect on the client (future task)
- Migrate RxJS streams to Effect (separate task dh-07h)
- Advanced WebSocket features (rooms, namespaces, binary)

## Current State

**Server (`packages/deep-heating-socketio`):**

- `SocketServer` class wraps Socket.IO server
- RxJS `fromEvent()` converts socket events to observables
- Broadcasts `State` to all clients on state change
- Receives `adjust_room` events from clients

**Client (`packages/deep-heating-web`):**

- `socket.io-client` library
- Svelte stores expose connection status and state
- Sends `adjust_room` events

## Design

### Message Protocol

Shared Schema-validated types in `deep-heating-types`:

```
ServerMessage = { type: "State", data: DeepHeatingState }
ClientMessage = { type: "adjust_room", data: RoomAdjustment }
```

### Server Architecture

**Layers:**

1. **ConnectionManager** - Tracks connected sockets for broadcast
   - `Ref<HashMap<Symbol, WriteFunc>>` internally
   - `add(id, write)` - register connection
   - `remove(id)` - unregister connection
   - `broadcast(message)` - send to all connections

2. **WebSocket Handler** - Pure function handling each connection
   - Get writer from socket
   - Register with ConnectionManager
   - Send current state on connect
   - Handle incoming messages (adjust_room)
   - Cleanup on disconnect via Effect.ensuring

3. **SocketServer** - `BunSocketServer.layerWebSocket` from @effect/platform-bun

**State Broadcasting:**

- Keep existing `maintainState()` RxJS Observable
- Subscribe to it and call `ConnectionManager.broadcast()` on each update
- Clean RxJS→Effect boundary (full RxJS migration is separate task)

### Client Architecture

**Native WebSocket:**

- Replace `socket.io-client` with browser's native `WebSocket` API
- Schema validation for type safety on received messages
- Simple reconnection wrapper with exponential backoff

**Svelte Stores:**

- Same pattern as current, different underlying API
- `onopen`/`onclose` for connection status
- `onmessage` with Schema decode for state updates

### File Changes

**Server:**

- `packages/deep-heating-socketio/src/app/socket-server.ts` - DELETE
- `packages/deep-heating-socketio/src/app/ConnectionManager.ts` - NEW
- `packages/deep-heating-socketio/src/app/websocket-handler.ts` - NEW
- `packages/deep-heating-socketio/src/server.ts` - Modify to use new Layers

**Client:**

- `packages/deep-heating-web/src/lib/stores/apiClient.ts` - Replace with native WebSocket
- `packages/deep-heating-web/src/lib/stores/home.ts` - Update for native WebSocket API

**Shared:**

- `packages/deep-heating-types/src/websocket.ts` - NEW message schemas

### Dependencies

**Add:** None (ws comes transitively via @effect/platform-node-shared)

**Remove:**

- `socket.io`
- `socket.io-client`
- `bufferutil` (optional)
- `utf-8-validate` (optional)

## Migration Plan

1. Add WebSocket message schemas to deep-heating-types
2. Create ConnectionManager Layer
3. Create WebSocket handler
4. Add `/ws` endpoint alongside existing Socket.IO
5. Update client to use native WebSocket
6. Test both endpoints work
7. Remove Socket.IO code and dependencies

No backwards compatibility needed - client and server deploy together as one add-on.

## Testing

- Unit tests for ConnectionManager (add/remove/broadcast)
- Unit tests for message encoding/decoding
- Integration test: connect, receive state, send adjustment, verify update
- Manual test in Home Assistant environment

## Risks

**Low:** `ws` library compatibility with Bun - mitigated by @effect/platform already using it

**Low:** Native WebSocket reconnection - simple exponential backoff sufficient for this use case
