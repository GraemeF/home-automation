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

const waitForConnection = (ws: WebSocket): Effect.Effect<void, Error, never> =>
  Effect.async((resume) => {
    if (ws.readyState === WebSocket.OPEN) {
      resume(Effect.void);
      return;
    }
    ws.addEventListener('open', () => resume(Effect.void));
    ws.addEventListener('error', (e) =>
      resume(Effect.fail(new Error(`WebSocket error: ${e}`))),
    );
  });

const waitForMessage = (ws: WebSocket): Effect.Effect<unknown, Error, never> =>
  Effect.async((resume) => {
    const timeoutId = setTimeout(
      () => resume(Effect.fail(new Error('Timeout waiting for message'))),
      5000,
    );
    ws.addEventListener('message', (event) => {
      clearTimeout(timeoutId);
      resume(Effect.succeed(JSON.parse(event.data as string)));
    });
    ws.addEventListener('error', (e) => {
      clearTimeout(timeoutId);
      resume(Effect.fail(new Error(`WebSocket error: ${e}`)));
    });
  });

const createTestServer = (
  port: number,
): Effect.Effect<WebSocketServer, never, never> =>
  createAndStartWebSocketServer({ port, path: '/ws' });

const sleep = (ms: number): Effect.Effect<void, never, never> =>
  Effect.promise(() => new Promise((resolve) => setTimeout(resolve, ms)));

const delayThenRun = <A, E>(
  ms: number,
  effect: Effect.Effect<A, E, never>,
): Effect.Effect<A, E, never> => Effect.flatMap(sleep(ms), () => effect);

// =============================================================================
// Integration Tests
// =============================================================================

describe('WebSocket Server Integration', () => {
  it.scoped('should accept WebSocket connections', () => {
    const port = getRandomPort();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          Effect.flatMap(waitForConnection),
          Effect.tap(() =>
            Effect.sync(() => {
              expect(true).toBe(true); // Connection succeeded
            }),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });

  it.scoped('should send current state to newly connected client', () => {
    const port = getRandomPort();
    const testState = createTestState();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          // Broadcast state first
          server.broadcast(testState),
          // Then connect client
          Effect.andThen(
            Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          ),
          Effect.flatMap((ws) =>
            pipe(waitForConnection(ws), Effect.andThen(waitForMessage(ws))),
          ),
          Effect.tap((message) =>
            Effect.sync(() => {
              const decoded = Schema.decodeUnknownSync(ServerMessage)(message);
              expect(decoded.type).toBe('state');
              if (decoded.type === 'state') {
                expect(decoded.data.rooms).toHaveLength(1);
                expect(decoded.data.rooms[0].name).toBe('Living Room');
              }
            }),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });

  it.scoped('should broadcast state updates to all connected clients', () => {
    const port = getRandomPort();
    const testState = createTestState();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          // Connect two clients
          Effect.all([
            Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
            Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          ]),
          Effect.flatMap(([ws1, ws2]) =>
            pipe(
              Effect.all([waitForConnection(ws1), waitForConnection(ws2)]),
              Effect.andThen(
                Effect.all(
                  [
                    waitForMessage(ws1),
                    waitForMessage(ws2),
                    delayThenRun(50, server.broadcast(testState)),
                  ],
                  { concurrency: 'unbounded' },
                ),
              ),
            ),
          ),
          Effect.tap(([msg1, msg2]) =>
            Effect.sync(() => {
              const decoded1 = Schema.decodeUnknownSync(ServerMessage)(msg1);
              const decoded2 = Schema.decodeUnknownSync(ServerMessage)(msg2);
              expect(decoded1.type).toBe('state');
              expect(decoded2.type).toBe('state');
            }),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });

  it.scoped('should receive room adjustments from clients', () => {
    const port = getRandomPort();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          Effect.flatMap((ws) =>
            pipe(
              waitForConnection(ws),
              Effect.andThen(
                Effect.all(
                  [
                    // Listen for adjustments
                    Effect.promise(() =>
                      firstValueFrom(
                        server.roomAdjustments$.pipe(take(1), timeout(5000)),
                      ),
                    ),
                    delayThenRun(
                      50,
                      Effect.sync(() => {
                        const adjustment: RoomAdjustment = {
                          roomName: 'Living Room',
                          adjustment: 1.5,
                        };
                        const message = Schema.encodeSync(ClientMessage)({
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
            ),
          ),
          Effect.tap(([received]) =>
            Effect.sync(() => {
              expect(received.roomName).toBe('Living Room');
              expect(received.adjustment).toBe(1.5);
            }),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });

  it.scoped('should handle multiple room adjustments', () => {
    const port = getRandomPort();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          Effect.flatMap((ws) =>
            pipe(
              waitForConnection(ws),
              Effect.andThen(
                Effect.all(
                  [
                    // Listen for adjustments
                    Effect.promise(() =>
                      firstValueFrom(
                        server.roomAdjustments$.pipe(
                          take(3),
                          toArray(),
                          timeout(5000),
                        ),
                      ),
                    ),
                    delayThenRun(
                      50,
                      Effect.sync(() => {
                        const adjustments: readonly RoomAdjustment[] = [
                          { roomName: 'Living Room', adjustment: 1.0 },
                          { roomName: 'Bedroom', adjustment: -0.5 },
                          { roomName: 'Kitchen', adjustment: 2.0 },
                        ];
                        adjustments.forEach((adjustment) => {
                          const message = Schema.encodeSync(ClientMessage)({
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
            ),
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
        ),
      ),
    );
  });

  it.scoped('should ignore malformed messages', () => {
    const port = getRandomPort();
    const testState = createTestState();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          Effect.flatMap((ws) =>
            pipe(
              waitForConnection(ws),
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
              Effect.andThen(
                Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
              ),
              Effect.flatMap((ws2) =>
                pipe(
                  waitForConnection(ws2),
                  Effect.andThen(
                    Effect.all(
                      [
                        waitForMessage(ws2),
                        delayThenRun(50, server.broadcast(testState)),
                      ],
                      { concurrency: 'unbounded' },
                    ),
                  ),
                ),
              ),
              Effect.tap(([message]) =>
                Effect.sync(() => {
                  expect(message).toBeDefined();
                }),
              ),
            ),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });

  it.scoped('should complete roomAdjustments$ observable on shutdown', () => {
    const port = getRandomPort();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) => {
        let completed = false;
        server.roomAdjustments$.subscribe({
          complete: () => {
            completed = true;
          },
        });

        return pipe(
          server.shutdown,
          Effect.tap(() =>
            Effect.sync(() => {
              expect(completed).toBe(true);
            }),
          ),
        );
      }),
    );
  });
});

describe('WebSocket Server - Edge Cases', () => {
  it.scoped('should handle client disconnection gracefully', () => {
    const port = getRandomPort();
    const testState = createTestState();

    return pipe(
      createTestServer(port),
      Effect.flatMap((server) =>
        pipe(
          // Connect two clients
          Effect.all([
            Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
            Effect.sync(() => new WebSocket(`ws://localhost:${port}/ws`)),
          ]),
          Effect.flatMap(([ws1, ws2]) =>
            pipe(
              Effect.all([waitForConnection(ws1), waitForConnection(ws2)]),
              // Disconnect first client
              Effect.tap(Effect.sync(ws1.close.bind(ws1))),
              // Wait for disconnection
              Effect.andThen(sleep(100)),
              // Broadcast to remaining client
              Effect.andThen(
                Effect.all(
                  [
                    waitForMessage(ws2),
                    delayThenRun(50, server.broadcast(testState)),
                  ],
                  { concurrency: 'unbounded' },
                ),
              ),
            ),
          ),
          Effect.tap(([message]) =>
            Effect.sync(() => {
              const decoded = Schema.decodeUnknownSync(ServerMessage)(message);
              expect(decoded.type).toBe('state');
            }),
          ),
          Effect.ensuring(server.shutdown),
        ),
      ),
    );
  });
});
