# Replace Socket.IO with Bun Native WebSocket

**Issue:** dh-mdh
**Date:** 2025-11-30
**Status:** Design Complete

## Overview

Replace Socket.IO with Bun's native WebSocket server using Effect patterns adapted from the brownsauce `eventsourcing-transport-websocket` package. This provides proper Effect lifecycle management without the complexity of Socket.IO.

## Goals

- Unified Effect architecture throughout the server
- Type-safe message protocol with Schema validation
- Proper Effect lifecycle management (Scope, Ref, HashMap)
- Remove Socket.IO dependency and complexity
- Rename package to reflect its new purpose

## Non-Goals

- Effect on the client (future task)
- Migrate RxJS streams to Effect (separate task dh-07h)
- Advanced WebSocket features (rooms, namespaces, binary)
- Generic transport abstraction layer (overkill for this use case)

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

### Patterns from Brownsauce

The implementation adapts patterns from `brownsauce/packages/eventsourcing-transport-websocket`:

1. **`Bun.serve()` with WebSocket handlers** - Direct use of Bun's WebSocket API
2. **`Effect.runSync` at callback boundaries** - WebSocket `open`/`message`/`close` handlers are sync callbacks, so we run Effects synchronously at these boundaries
3. **`HashMap<ClientId, ClientState>` for connection tracking** - Per-client state management
4. **Queue-based message distribution** - Using Effect's `Queue` for pub/sub
5. **Branded types** - `ClientId` for type safety

We skip brownsauce's generic `TransportMessage` envelope and transport abstraction layer - deep-heating just needs State broadcasts and adjust_room messages.

### Message Protocol

Shared Schema-validated types in `deep-heating-types`:

```typescript
// Server → Client
const ServerMessage = Schema.Union(Schema.Struct({ type: Schema.Literal('state'), data: DeepHeatingStateSchema }));

// Client → Server
const ClientMessage = Schema.Union(Schema.Struct({ type: Schema.Literal('adjust_room'), data: RoomAdjustmentSchema }));
```

### Server Architecture

**Package rename:** `deep-heating-socketio` → `deep-heating-server`

**Layers:**

1. **ClientState** - Per-connection state

   ```typescript
   interface ClientState {
     readonly id: ClientId;
     readonly socket: ServerWebSocket<WebSocketData>;
     readonly connectedAt: Date;
   }
   ```

2. **ServerState** - All connections

   ```typescript
   interface ServerState {
     readonly server: Bun.Server | null;
     readonly clients: HashMap<ClientId, ClientState>;
   }
   ```

3. **WebSocket Server** - `Bun.serve()` with handlers
   - `open`: Create ClientState, add to HashMap, send current state
   - `message`: Parse with Schema, handle adjust_room
   - `close`: Remove from HashMap, cleanup

4. **Broadcast** - Iterate HashMap, send to each client
   ```typescript
   const broadcast = (message: ServerMessage) =>
     pipe(
       serverStateRef,
       Ref.get,
       Effect.flatMap((state) => Effect.forEach(HashMap.values(state.clients), sendToClient(message))),
     );
   ```

**State Broadcasting:**

- Keep existing `maintainState()` RxJS Observable
- Subscribe to it and call `broadcast()` on each update
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

**Package Rename:**

- `packages/deep-heating-socketio/` → `packages/deep-heating-server/`
- Update `package.json` name: `@home-automation/deep-heating-socketio` → `@home-automation/deep-heating-server`
- Update all workspace references

**Server (in `packages/deep-heating-server/`):**

- `src/app/socket-server.ts` - DELETE
- `src/app/websocket-server.ts` - NEW (Bun.serve with WebSocket handlers)
- `src/server.ts` - Modify to use new WebSocket server

**Client:**

- `packages/deep-heating-web/src/lib/stores/apiClient.ts` - Replace with native WebSocket
- `packages/deep-heating-web/src/lib/stores/home.ts` - Update for native WebSocket API

**Shared:**

- `packages/deep-heating-types/src/websocket.ts` - NEW message schemas

### Dependencies

**Add:** None (Bun has native WebSocket support)

**Remove:**

- `socket.io`
- `socket.io-client`
- `bufferutil` (optional)
- `utf-8-validate` (optional)

## Migration Plan

1. Add WebSocket message schemas to deep-heating-types
2. Rename package deep-heating-socketio → deep-heating-server
3. Create WebSocket server using Bun.serve() patterns
4. Update server.ts to use new WebSocket server
5. Update client to use native WebSocket
6. Remove Socket.IO code and dependencies
7. Run tests and verify everything works

No backwards compatibility needed - client and server deploy together as one add-on.

## Testing

- Unit tests for message encoding/decoding
- Unit tests for WebSocket server (connection, broadcast, message handling)
- Integration test: connect, receive state, send adjustment, verify update
- Manual test in Home Assistant environment

## Risks

**Low:** Bun WebSocket API differences from Node - mitigated by using Bun's native API directly

**Low:** Native WebSocket reconnection - simple exponential backoff sufficient for this use case
