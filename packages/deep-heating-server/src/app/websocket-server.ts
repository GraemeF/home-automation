/**
 * WebSocket Server Implementation
 *
 * A WebSocket server using Bun's native WebSocket API with Effect patterns.
 * Adapted from brownsauce eventsourcing-transport-websocket patterns.
 */

import { Brand, Effect, HashMap, pipe, Ref, Schema } from 'effect';
import {
  ClientMessage,
  DeepHeatingState,
  RoomAdjustment,
  ServerMessageEncoded,
} from '@home-automation/deep-heating-types';
import { Observable, Subject, Subscription } from 'rxjs';

// =============================================================================
// Branded Types
// =============================================================================

type ClientId = string & Brand.Brand<'ClientId'>;
const ClientId = Brand.nominal<ClientId>();

// =============================================================================
// Internal State Types
// =============================================================================

interface WebSocketData {
  readonly clientId?: ClientId;
}

interface ClientState {
  readonly id: ClientId;
  readonly socket: Bun.ServerWebSocket<WebSocketData>;
  readonly connectedAt: Readonly<Date>;
}

interface ServerState {
  readonly server: Bun.Server<WebSocketData> | null;
  readonly clients: HashMap.HashMap<ClientId, Readonly<ClientState>>;
}

interface WebSocketServerConfig {
  readonly port: number;
  readonly path: string;
}

// =============================================================================
// Pure Functions for Client Management
// =============================================================================

const createAddClientToServerStateUpdater =
  (clientState: Readonly<ClientState>) => (state: ServerState) => ({
    ...state,
    clients: HashMap.set(state.clients, clientState.id, clientState),
  });

const addClientToServerState = (
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  clientState: Readonly<ClientState>,
): Effect.Effect<void, never, never> =>
  Ref.update(serverStateRef, createAddClientToServerStateUpdater(clientState));

const createRemoveClientFromServerStateUpdater =
  (clientId: ClientId) => (s: ServerState) => ({
    ...s,
    clients: HashMap.remove(s.clients, clientId),
  });

const removeClientFromServerState = (
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  clientId: ClientId,
): Effect.Effect<void, never, never> =>
  Ref.update(
    serverStateRef,
    createRemoveClientFromServerStateUpdater(clientId),
  );

// =============================================================================
// Message Handling
// =============================================================================

const parseClientMessage = (data: Readonly<string>) =>
  pipe(
    Effect.try(() => JSON.parse(data) as unknown),
    Effect.flatMap(Schema.decodeUnknown(ClientMessage)),
  );

const handleClientMessage =
  (roomAdjustmentSubject: Subject<RoomAdjustment>) =>
  (data: Readonly<string>): Effect.Effect<void, never, never> =>
    pipe(
      parseClientMessage(data),
      Effect.tap((message) =>
        Effect.sync(() => {
          if (message.type === 'adjust_room') {
            roomAdjustmentSubject.next(message.data);
          }
        }),
      ),
      Effect.catchAll(() => Effect.void),
    );

// =============================================================================
// Broadcasting
// =============================================================================

const encodeServerMessage = (
  state: Readonly<DeepHeatingState>,
): ServerMessageEncoded => ({
  type: 'state',
  data: Schema.encodeSync(DeepHeatingState)(state),
});

const sendToSingleClient =
  (message: Readonly<ServerMessageEncoded>) =>
  (clientState: Readonly<ClientState>): Effect.Effect<void, never, never> =>
    Effect.try({
      try: () => {
        const serialized = JSON.stringify(message);
        clientState.socket.send(serialized);
      },
      catch: () => undefined,
    }).pipe(Effect.catchAll(() => Effect.void));

const broadcastToAllClients = (
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  message: Readonly<ServerMessageEncoded>,
): Effect.Effect<void, never, never> =>
  pipe(
    serverStateRef,
    Ref.get,
    Effect.flatMap((state) =>
      Effect.forEach(
        HashMap.values(state.clients),
        sendToSingleClient(message),
        {
          discard: true,
        },
      ),
    ),
    Effect.asVoid,
  );

// =============================================================================
// WebSocket Server
// =============================================================================

const createWebSocketServer = (
  config: Readonly<WebSocketServerConfig>,
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  roomAdjustmentSubject: Subject<RoomAdjustment>,
  currentState: Readonly<Ref.Ref<DeepHeatingState | null>>,
): Effect.Effect<Bun.Server<WebSocketData>, never, never> =>
  Effect.sync(() => {
    const server = Bun.serve<WebSocketData>({
      port: config.port,
      websocket: {
        open: (ws: Bun.ServerWebSocket<WebSocketData>) => {
          const clientId = ClientId(`client-${crypto.randomUUID()}`);
          const connectedAt = new Date();

          const clientState: ClientState = {
            id: clientId,
            socket: ws,
            connectedAt,
          };

          // eslint-disable-next-line functional/immutable-data -- Bun WebSocket API requires mutating data property
          ws.data = { clientId };

          // eslint-disable-next-line effect/no-runSync -- WebSocket open handler is a sync callback at application boundary
          Effect.runSync(
            pipe(
              addClientToServerState(serverStateRef, clientState),
              Effect.andThen(Ref.get(currentState)),
              Effect.tap((state) =>
                state !== null
                  ? sendToSingleClient(encodeServerMessage(state))(clientState)
                  : Effect.void,
              ),
            ),
          );
        },

        message: (
          ws: Bun.ServerWebSocket<WebSocketData>,
          message: string | Buffer,
        ) => {
          const data =
            typeof message === 'string' ? message : message.toString();
          // eslint-disable-next-line effect/no-runSync -- WebSocket message handler is a sync callback at application boundary
          Effect.runSync(handleClientMessage(roomAdjustmentSubject)(data));
        },

        close: (ws: Bun.ServerWebSocket<WebSocketData>) => {
          if (!ws.data.clientId) return;
          // eslint-disable-next-line effect/no-runSync -- WebSocket close handler is a sync callback at application boundary
          Effect.runSync(
            removeClientFromServerState(serverStateRef, ws.data.clientId),
          );
        },
      },

      fetch: (req, server) => {
        const url = new URL(req.url);
        if (url.pathname === config.path) {
          const success = server.upgrade(req, { data: {} });
          return success
            ? undefined
            : new Response('WebSocket upgrade failed', { status: 400 });
        }
        return new Response('Not Found', { status: 404 });
      },
    });

    return server;
  });

// =============================================================================
// Public API
// =============================================================================

export interface WebSocketServer {
  readonly roomAdjustments$: Observable<RoomAdjustment>;
  readonly broadcast: (
    state: Readonly<DeepHeatingState>,
  ) => Effect.Effect<void, never, never>;
  readonly shutdown: Effect.Effect<void, never, never>;
}

const broadcastStateToClients = (
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  currentStateRef: Readonly<Ref.Ref<DeepHeatingState | null>>,
  state: Readonly<DeepHeatingState>,
): Effect.Effect<void, never, never> =>
  pipe(
    Ref.set(currentStateRef, state),
    Effect.andThen(
      broadcastToAllClients(serverStateRef, encodeServerMessage(state)),
    ),
  );

const shutdownServerAndCleanup = (
  server: Bun.Server<WebSocketData>,
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  roomAdjustmentSubject: Subject<RoomAdjustment>,
): Effect.Effect<void, never, never> =>
  pipe(
    Ref.get(serverStateRef),
    Effect.tap((state) =>
      Effect.sync(() => {
        try {
          Array.from(HashMap.values(state.clients)).forEach((clientState) => {
            try {
              clientState.socket.close(1001, 'Server shutting down');
            } catch {
              // Ignore errors during cleanup
            }
          });
          server.stop();
        } catch {
          // Ignore cleanup errors
        }
      }),
    ),
    Effect.tap(() =>
      Effect.sync(() => {
        roomAdjustmentSubject.complete();
      }),
    ),
    Effect.asVoid,
  );

const initializeServerWithWebSocket = (
  config: Readonly<WebSocketServerConfig>,
  serverStateRef: Readonly<Ref.Ref<ServerState>>,
  currentStateRef: Readonly<Ref.Ref<DeepHeatingState | null>>,
  roomAdjustmentSubject: Subject<RoomAdjustment>,
): Effect.Effect<WebSocketServer, never, never> =>
  pipe(
    createWebSocketServer(
      config,
      serverStateRef,
      roomAdjustmentSubject,
      currentStateRef,
    ),
    Effect.tap((server) =>
      Ref.update(serverStateRef, (state) => ({ ...state, server })),
    ),
    Effect.map(
      (server): WebSocketServer => ({
        roomAdjustments$: roomAdjustmentSubject.asObservable(),

        broadcast: (state: Readonly<DeepHeatingState>) =>
          broadcastStateToClients(serverStateRef, currentStateRef, state),

        shutdown: shutdownServerAndCleanup(
          server,
          serverStateRef,
          roomAdjustmentSubject,
        ),
      }),
    ),
  );

export const createAndStartWebSocketServer = (
  config: Readonly<WebSocketServerConfig>,
): Effect.Effect<WebSocketServer, never, never> =>
  pipe(
    Effect.all({
      serverStateRef: Ref.make<ServerState>({
        server: null,
        clients: HashMap.empty(),
      }),
      currentStateRef: Ref.make<DeepHeatingState | null>(null),
      roomAdjustmentSubject: Effect.sync(() => new Subject<RoomAdjustment>()),
    }),
    Effect.flatMap(
      ({ serverStateRef, currentStateRef, roomAdjustmentSubject }) =>
        initializeServerWithWebSocket(
          config,
          serverStateRef,
          currentStateRef,
          roomAdjustmentSubject,
        ),
    ),
  );

/**
 * Subscribes to a state observable and broadcasts updates to all WebSocket clients.
 * Returns the subscription for cleanup.
 */
export const subscribeAndBroadcast = (
  wsServer: WebSocketServer,
  state$: Observable<DeepHeatingState>,
  // eslint-disable-next-line functional/prefer-immutable-types -- RxJS Subscription is inherently mutable
): Subscription =>
  state$.subscribe((state) => {
    // eslint-disable-next-line effect/no-runSync -- RxJS callback boundary, cannot use Effect composition
    Effect.runSync(wsServer.broadcast(state));
  });
