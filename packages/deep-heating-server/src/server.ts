import { FetchHttpClient, FileSystem } from '@effect/platform';
import { BunFileSystem } from '@effect/platform-bun';
import { Effect, Layer, pipe, Schema, Scope } from 'effect';
import {
  HomeAssistantApiLive,
  HomeAssistantConfigLive,
  HomeAssistantHeatingSystemLive,
} from '@home-automation/deep-heating-home-assistant';
import {
  HeatingSystem,
  Home,
  RoomAdjustment,
} from '@home-automation/deep-heating-types';
import { createDeepHeating } from '@home-automation/deep-heating-rx';
import { maintainState } from '@home-automation/deep-heating-state';
import { throttleTime } from 'rxjs/operators';
import {
  createAndStartWebSocketServer,
  subscribeAndBroadcast,
  type WebSocketServer,
} from './app/websocket-server';
import { createHeatingSystemAdapter } from './app/heatingSystemAdapter';

export interface ServerConfig {
  readonly port: number;
  readonly homeConfigPath: string;
  readonly roomAdjustmentsPath: string;
  readonly websocketPath: string;
}

const RoomAdjustmentSchema = Schema.Struct({
  roomName: Schema.String,
  adjustment: Schema.Number,
}) satisfies Schema.Schema<RoomAdjustment, RoomAdjustment>;

const JsonHomeData = Schema.parseJson(Home);
const JsonRoomAdjustments = Schema.parseJson(
  Schema.Array(RoomAdjustmentSchema),
);

/**
 * Layer that provides HomeAssistantApi with all required dependencies.
 * Composed at the application level for proper Effect lifecycle management.
 */
const HomeAssistantLayer = HomeAssistantApiLive.pipe(
  Layer.provide(HomeAssistantConfigLive),
  Layer.provide(FetchHttpClient.layer),
);

const loadRoomAdjustments = (
  fs: FileSystem.FileSystem,
  roomAdjustmentsPath: string,
): Effect.Effect<readonly RoomAdjustment[]> =>
  pipe(
    roomAdjustmentsPath,
    fs.readFileString,
    Effect.flatMap(Schema.decode(JsonRoomAdjustments)),
    Effect.catchAll(() => Effect.succeed([] as readonly RoomAdjustment[])),
  );

const startHeatingSystem = (
  wsServer: WebSocketServer,
  home: Home,
  initialRoomAdjustments: readonly RoomAdjustment[],
  roomAdjustmentsPath: string,
): Effect.Effect<void, never, Scope.Scope | HeatingSystem> =>
  pipe(
    HeatingSystem,
    Effect.flatMap((heatingSystem) =>
      Effect.sync(() => {
        // Create the adapter that bridges HeatingSystem to HeatingSystemStreams
        const { streams, cleanup } = createHeatingSystemAdapter(heatingSystem);

        // Create the deep heating reactive system
        const deepHeating = createDeepHeating(
          home,
          [...initialRoomAdjustments],
          wsServer.roomAdjustments$,
          streams,
        );

        // Maintain state with throttling
        const state$ = maintainState(deepHeating).pipe(
          throttleTime(100, undefined, { leading: true, trailing: true }),
        );

        // Subscribe to state changes and broadcast to WebSocket clients
        const broadcastSubscription = subscribeAndBroadcast(wsServer, state$);

        // Save room adjustments on state changes
        const saveSubscription = state$.subscribe((state) => {
          const roomAdjustments = state.rooms.map((room) => ({
            roomName: room.name,
            adjustment: room.adjustment,
          }));
          // Fire-and-forget async write using Bun native API
          void Bun.write(roomAdjustmentsPath, JSON.stringify(roomAdjustments));
        });

        return { broadcastSubscription, saveSubscription, cleanup };
      }),
    ),
    Effect.tap(({ cleanup }) =>
      Effect.addFinalizer(() =>
        Effect.sync(() => {
          cleanup();
        }),
      ),
    ),
    Effect.asVoid,
  );

const createWebSocketServerWithLogging = (
  port: number,
  path: string,
): Effect.Effect<WebSocketServer, never, Scope.Scope> =>
  pipe(
    { port, path },
    createAndStartWebSocketServer,
    Effect.tap(() =>
      Effect.log(`WebSocket server listening on port ${String(port)}`),
    ),
  );

const shutdownWebSocketServerWithLogging = (
  wsServer: WebSocketServer,
): Effect.Effect<void> =>
  pipe(
    'Shutting down WebSocket server...',
    Effect.log,
    Effect.andThen(wsServer.shutdown),
    Effect.andThen(Effect.log('Server shut down')),
  );

const runHeatingSystemWithCleanup = (
  wsServer: WebSocketServer,
  home: Home,
  initialRoomAdjustments: readonly RoomAdjustment[],
  roomAdjustmentsPath: string,
): Effect.Effect<never, never, Scope.Scope | HeatingSystem> =>
  pipe(
    startHeatingSystem(
      wsServer,
      home,
      initialRoomAdjustments,
      roomAdjustmentsPath,
    ),
    Effect.zipRight(
      Effect.addFinalizer(() => shutdownWebSocketServerWithLogging(wsServer)),
    ),
    Effect.zipRight(Effect.never),
  );

const setupWebSocketServerAndRunHeatingSystem = (
  home: Home,
  initialRoomAdjustments: readonly RoomAdjustment[],
  config: ServerConfig,
): Effect.Effect<never, never, Scope.Scope | HeatingSystem> =>
  pipe(
    createWebSocketServerWithLogging(config.port, config.websocketPath),
    Effect.flatMap((wsServer) =>
      runHeatingSystemWithCleanup(
        wsServer,
        home,
        initialRoomAdjustments,
        config.roomAdjustmentsPath,
      ),
    ),
  );

const startServer = (
  fs: FileSystem.FileSystem,
  home: Home,
  config: ServerConfig,
): Effect.Effect<void, never, Scope.Scope | HeatingSystem> =>
  pipe(
    loadRoomAdjustments(fs, config.roomAdjustmentsPath),
    Effect.tap((adjustments) =>
      Effect.log(`Loaded ${String(adjustments.length)} room adjustments`),
    ),
    Effect.flatMap((initialRoomAdjustments) =>
      setupWebSocketServerAndRunHeatingSystem(
        home,
        initialRoomAdjustments,
        config,
      ),
    ),
  );

/**
 * Creates a HeatingSystem layer for production use with Home Assistant.
 */
const createHeatingSystemLayer = (home: Home) =>
  HomeAssistantHeatingSystemLive(home).pipe(Layer.provide(HomeAssistantLayer));

const startServerWithHeatingSystem = (
  fs: FileSystem.FileSystem,
  home: Home,
  config: ServerConfig,
) =>
  pipe(
    startServer(fs, home, config),
    Effect.provide(createHeatingSystemLayer(home)),
  );

const loadAndStartServer = (fs: FileSystem.FileSystem, config: ServerConfig) =>
  pipe(
    config.homeConfigPath,
    fs.readFileString,
    Effect.andThen(Schema.decode(JsonHomeData)),
    Effect.tap((home) =>
      Effect.log(
        `Home configuration loaded: ${String(home.rooms.length)} rooms`,
      ),
    ),
    Effect.andThen((home) => startServerWithHeatingSystem(fs, home, config)),
  );

/**
 * Runs the WebSocket server as an Effect application with proper lifecycle management.
 * The server will run until interrupted (e.g., SIGINT/SIGTERM).
 */
export const runServer = (config: ServerConfig) =>
  pipe(
    Effect.void,
    Effect.andThen(() => FileSystem.FileSystem),
    Effect.andThen((fs) => loadAndStartServer(fs, config)),
    Effect.scoped,
    Effect.provide(BunFileSystem.layer),
  );
