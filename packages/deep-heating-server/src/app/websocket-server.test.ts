/**
 * WebSocket Server Integration Tests
 *
 * Tests the WebSocket server implementation with real connections.
 * Uses random ports to avoid conflicts.
 */

import { describe, it, expect } from '@codeforbreakfast/bun-test-effect';
import { Effect, Option, pipe, Schema } from 'effect';
import {
  createAndStartWebSocketServer,
  type WebSocketServer,
} from './websocket-server';
import {
  DeepHeatingState,
  ServerMessage,
  ClientMessage,
  type RoomAdjustment,
} from '@home-automation/deep-heating-types';
import { firstValueFrom, take, toArray, timeout } from 'rxjs';

// =============================================================================
// Test Utilities
// =============================================================================

// Schema wrapper functions to avoid curried calls
const decodeServerMessage = Schema.decodeUnknownSync(ServerMessage);

const encodeClientMessage = Schema.encodeSync(ClientMessage);

const getRandomPort = () => Math.floor(Math.random() * (65535 - 49152) + 49152);

const createTestState = (): DeepHeatingState => ({
  rooms: [
    {
      name: 'Living Room',
      temperature: Option.some({ temperature: 20, time: new Date() }),
      targetTemperature: Option.some(21),
      radiators: [],
      mode: Option.some('Auto' as const),
      isHeating: Option.some(true),
      adjustment: 0,
    },
  ],
  isHeating: Option.some(true),
});

const waitForConnection = (ws: WebSocket): Effect.Effect<void, Error> =>
  Effect.async((resume) => {
    if (ws.readyState === WebSocket.OPEN) {
      resume(Effect.void);
      return;
    }
    ws.addEventListener('open', () => {
      resume(Effect.void);
    });
    ws.addEventListener('error', (e) => {
      resume(Effect.fail(new Error(`WebSocket error: ${e.type}`)));
    });
  });

const waitForMessage = (ws: WebSocket): Effect.Effect<unknown, Error> =>
  Effect.async((resume) => {
    const timeoutId = setTimeout(() => {
      resume(Effect.fail(new Error('Timeout waiting for message')));
    }, 5000);
    ws.addEventListener('message', (event) => {
      clearTimeout(timeoutId);
      resume(Effect.succeed(JSON.parse(event.data as string)));
    });
    ws.addEventListener('error', (e) => {
      clearTimeout(timeoutId);
      resume(Effect.fail(new Error(`WebSocket error: ${e.type}`)));
    });
  });

const createTestServer = (port: number): Effect.Effect<WebSocketServer> =>
  createAndStartWebSocketServer({ port, path: '/ws' });

const sleep = (ms: number): Effect.Effect<void> =>
  Effect.promise(() => new Promise((resolve) => setTimeout(resolve, ms)));

const delayThenRun = <A, E>(
  ms: number,
  effect: Effect.Effect<A, E>,
): Effect.Effect<A, E> => Effect.flatMap(sleep(ms), () => effect);

const connectToWebSocket = (port: number): Effect.Effect<void, Error> =>
  pipe(
    () => new WebSocket(`ws://localhost:${String(port)}/ws`),
    Effect.sync,
    Effect.flatMap(waitForConnection),
    Effect.tap(() =>
      Effect.sync(() => {
        expect(true).toBe(true); // Connection succeeded
      }),
    ),
  );

// =============================================================================
// Integration Tests
// =============================================================================

describe('WebSocket Server Integration', () => {
  it.scoped('should accept WebSocket connections', () => {
    const port = getRandomPort();

    return pipe(
      port,
      createTestServer,
      Effect.flatMap((server) =>
        Effect.ensuring(connectToWebSocket(port), server.shutdown),
      ),
    );
  });

  it.scoped('should send current state to newly connected client', () => {
    const port = getRandomPort();
    const testState = createTestState();

    const connectAndReceiveStateMessage = (
      ws: WebSocket,
    ): Effect.Effect<unknown, Error> =>
      pipe(ws, waitForConnection, Effect.andThen(waitForMessage(ws)));

    const createWebSocketEffect = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const broadcastAndVerifyState = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        // Broadcast state first
        testState,
        server.broadcast,
        // Then connect client
        Effect.andThen(createWebSocketEffect()),
        Effect.flatMap(connectAndReceiveStateMessage),
        Effect.tap((message) =>
          Effect.sync(() => {
            const decoded = decodeServerMessage(message);
            expect(decoded.type).toBe('state');
            // Type narrowing - decoded.type is already checked to be 'state'
            expect(decoded.data.rooms).toHaveLength(1);
            expect(decoded.data.rooms[0].name).toBe('Living Room');
          }),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(broadcastAndVerifyState),
    );
  });

  it.scoped('should broadcast state updates to all connected clients', () => {
    const port = getRandomPort();
    const testState = createTestState();

    const connectTwoClientsAndReceiveBroadcast = (
      ws1: WebSocket,
      ws2: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<readonly [unknown, unknown, unknown], Error> => {
      const broadcastTestState = pipe(testState, server.broadcast);
      return pipe(
        [waitForConnection(ws1), waitForConnection(ws2)],
        Effect.all,
        Effect.andThen(
          Effect.all(
            [
              waitForMessage(ws1),
              waitForMessage(ws2),
              delayThenRun(50, broadcastTestState),
            ],
            { concurrency: 'unbounded' },
          ),
        ),
      );
    };

    const createWebSocketEffect1 = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const createWebSocketEffect2 = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const verifyBroadcastToClients = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        // Connect two clients
        [createWebSocketEffect1(), createWebSocketEffect2()],
        Effect.all,
        Effect.flatMap(([ws1, ws2]) =>
          connectTwoClientsAndReceiveBroadcast(ws1, ws2, server),
        ),
        Effect.tap(([msg1, msg2]) =>
          Effect.sync(() => {
            const decoded1 = decodeServerMessage(msg1);
            const decoded2 = decodeServerMessage(msg2);
            expect(decoded1.type).toBe('state');
            expect(decoded2.type).toBe('state');
          }),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(verifyBroadcastToClients),
    );
  });

  it.scoped('should receive room adjustments from clients', () => {
    const port = getRandomPort();

    const sendRoomAdjustmentAndWaitForReceipt = (
      ws: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<readonly [RoomAdjustment, unknown], Error> => {
      const listenForAdjustment = pipe(
        () =>
          firstValueFrom(server.roomAdjustments$.pipe(take(1), timeout(5000))),
        Effect.promise,
      );

      return pipe(
        ws,
        waitForConnection,
        Effect.andThen(
          Effect.all(
            [
              // Listen for adjustments
              listenForAdjustment,
              delayThenRun(
                50,
                Effect.sync(() => {
                  const adjustment: RoomAdjustment = {
                    roomName: 'Living Room',
                    adjustment: 1.5,
                  };
                  const message = encodeClientMessage({
                    type: 'adjust_room',
                    data: adjustment,
                  });
                  ws.send(JSON.stringify(message));
                }),
              ),
            ],
            { concurrency: 'unbounded' },
          ),
        ),
      );
    };

    const verifyRoomAdjustmentReceived = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
        Effect.flatMap((ws) => sendRoomAdjustmentAndWaitForReceipt(ws, server)),
        Effect.tap(([received]) =>
          Effect.sync(() => {
            expect(received.roomName).toBe('Living Room');
            expect(received.adjustment).toBe(1.5);
          }),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(verifyRoomAdjustmentReceived),
    );
  });

  it.scoped('should handle multiple room adjustments', () => {
    const port = getRandomPort();

    const sendMultipleAdjustmentsAndWaitForReceipt = (
      ws: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<readonly [readonly RoomAdjustment[], unknown], Error> => {
      const listenForMultipleAdjustments = pipe(
        () =>
          firstValueFrom(
            server.roomAdjustments$.pipe(take(3), toArray(), timeout(5000)),
          ),
        Effect.promise,
      );

      return pipe(
        ws,
        waitForConnection,
        Effect.andThen(
          Effect.all(
            [
              // Listen for adjustments
              listenForMultipleAdjustments,
              delayThenRun(
                50,
                Effect.sync(() => {
                  const adjustments: readonly RoomAdjustment[] = [
                    { roomName: 'Living Room', adjustment: 1.0 },
                    { roomName: 'Bedroom', adjustment: -0.5 },
                    { roomName: 'Kitchen', adjustment: 2.0 },
                  ];
                  adjustments.forEach((adjustment) => {
                    const message = encodeClientMessage({
                      type: 'adjust_room',
                      data: adjustment,
                    });
                    ws.send(JSON.stringify(message));
                  });
                }),
              ),
            ],
            { concurrency: 'unbounded' },
          ),
        ),
      );
    };

    const verifyMultipleAdjustmentsReceived = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
        Effect.flatMap((ws) =>
          sendMultipleAdjustmentsAndWaitForReceipt(ws, server),
        ),
        Effect.tap(([received]) =>
          Effect.sync(() => {
            expect(received).toHaveLength(3);
            expect(received[0].roomName).toBe('Living Room');
            expect(received[1].roomName).toBe('Bedroom');
            expect(received[2].roomName).toBe('Kitchen');
          }),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(verifyMultipleAdjustmentsReceived),
    );
  });

  it.scoped('should ignore malformed messages', () => {
    const port = getRandomPort();
    const testState = createTestState();

    const connectSecondClientAndReceiveBroadcast = (
      ws2: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<readonly [unknown, unknown], Error> => {
      const broadcastTestState = pipe(testState, server.broadcast);
      return pipe(
        ws2,
        waitForConnection,
        Effect.andThen(
          Effect.all(
            [waitForMessage(ws2), delayThenRun(50, broadcastTestState)],
            { concurrency: 'unbounded' },
          ),
        ),
      );
    };

    const createWebSocketEffect3 = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const sendMalformedMessagesAndVerifyServerStillWorks = (
      ws: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<unknown, Error> =>
      pipe(
        ws,
        waitForConnection,
        // Send malformed messages
        Effect.tap(() =>
          Effect.sync(() => {
            ws.send('not json');
            ws.send('{"invalid": "message"}');
            ws.send('{"type": "unknown_type", "data": {}}');
          }),
        ),
        // Wait a bit
        Effect.andThen(sleep(100)),
        // Server should still work
        Effect.andThen(createWebSocketEffect3()),
        Effect.flatMap((ws2) =>
          connectSecondClientAndReceiveBroadcast(ws2, server),
        ),
        Effect.tap(([message]) =>
          Effect.sync(() => {
            expect(message).toBeDefined();
          }),
        ),
      );

    const verifyMalformedMessagesIgnored = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
        Effect.flatMap((ws) =>
          sendMalformedMessagesAndVerifyServerStillWorks(ws, server),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(verifyMalformedMessagesIgnored),
    );
  });

  it.scoped('should complete roomAdjustments$ observable on shutdown', () => {
    const port = getRandomPort();

    const shutdownAndVerifyCompletion = (
      server: WebSocketServer,
      completed: { readonly value: boolean },
    ): Effect.Effect<void> =>
      pipe(
        server.shutdown,
        Effect.tap(() =>
          Effect.sync(() => {
            expect(completed.value).toBe(true);
          }),
        ),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap((server) => {
        const completed = { value: false };
        server.roomAdjustments$.subscribe({
          complete: () => {
            completed.value = true;
          },
        });

        return shutdownAndVerifyCompletion(server, completed);
      }),
    );
  });
});

describe('WebSocket Server - Edge Cases', () => {
  it.scoped('should handle client disconnection gracefully', () => {
    const port = getRandomPort();
    const testState = createTestState();

    const disconnectFirstClientAndBroadcastToSecond = (
      ws1: WebSocket,
      ws2: WebSocket,
      server: WebSocketServer,
    ): Effect.Effect<readonly [unknown, unknown], Error> => {
      const boundClose = ws1.close.bind(ws1);
      const closeWebSocket = pipe(boundClose, Effect.sync);
      const broadcastTestState = pipe(testState, server.broadcast);
      return pipe(
        [waitForConnection(ws1), waitForConnection(ws2)],
        Effect.all,
        // Disconnect first client
        Effect.tap(closeWebSocket),
        // Wait for disconnection
        Effect.andThen(sleep(100)),
        // Broadcast to remaining client
        Effect.andThen(
          Effect.all(
            [waitForMessage(ws2), delayThenRun(50, broadcastTestState)],
            { concurrency: 'unbounded' },
          ),
        ),
      );
    };

    const createWebSocketEffect4 = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const createWebSocketEffect5 = (): Effect.Effect<WebSocket> =>
      pipe(
        () => new WebSocket(`ws://localhost:${String(port)}/ws`),
        Effect.sync,
      );

    const verifyDisconnectionHandling = (
      server: WebSocketServer,
    ): Effect.Effect<void, Error> =>
      pipe(
        // Connect two clients
        [createWebSocketEffect4(), createWebSocketEffect5()],
        Effect.all,
        Effect.flatMap(([ws1, ws2]) =>
          disconnectFirstClientAndBroadcastToSecond(ws1, ws2, server),
        ),
        Effect.tap(([message]) =>
          Effect.sync(() => {
            const decoded = decodeServerMessage(message);
            expect(decoded.type).toBe('state');
          }),
        ),
        Effect.ensuring(server.shutdown),
      );

    return pipe(
      port,
      createTestServer,
      Effect.flatMap(verifyDisconnectionHandling),
    );
  });
});
