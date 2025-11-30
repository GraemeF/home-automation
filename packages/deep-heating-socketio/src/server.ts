import { FileSystem } from '@effect/platform';
import { BunFileSystem } from '@effect/platform-bun';
import { Effect, pipe, Schema, Scope } from 'effect';
import { Home, RoomAdjustment } from '@home-automation/deep-heating-types';
// eslint-disable-next-line effect/prefer-effect-platform -- socket.io requires Node http.Server, cannot migrate to Effect Platform HttpServer
import { createServer, IncomingMessage, Server, ServerResponse } from 'http';
import { SocketServer } from './app/socket-server';

export interface ServerConfig {
  readonly port: number;
  readonly homeConfigPath: string;
  readonly roomAdjustmentsPath: string;
  readonly socketioPath: string;
  readonly corsOrigins: readonly string[];
}

const RoomAdjustmentSchema = Schema.Struct({
  roomName: Schema.String,
  adjustment: Schema.Number,
}) satisfies Schema.Schema<RoomAdjustment, RoomAdjustment>;

const JsonHomeData = Schema.parseJson(Home);
const JsonRoomAdjustments = Schema.parseJson(
  Schema.Array(RoomAdjustmentSchema),
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

const createSocketServer = (
  fs: FileSystem.FileSystem,
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  home: Home,
  config: ServerConfig,
): Effect.Effect<SocketServer, never, Scope.Scope> =>
  pipe(
    loadRoomAdjustments(fs, config.roomAdjustmentsPath),
    Effect.map((initialRoomAdjustments) => {
      const socketServer = new SocketServer(
        httpServer,
        home,
        [...initialRoomAdjustments],
        // Fire-and-forget async write using Bun native API
        // Note: callback is invoked from RxJS, not Effect context
        (roomAdjustments) =>
          // eslint-disable-next-line effect/prefer-effect-platform -- callback called from RxJS subscription, not Effect context
          void Bun.write(
            config.roomAdjustmentsPath,
            JSON.stringify(roomAdjustments),
          ),
        {
          path: config.socketioPath,
          cors: {
            origin: [...config.corsOrigins],
            methods: ['GET', 'POST', 'OPTIONS'],
          },
        },
      );
      return socketServer;
    }),
    Effect.tap(() => Effect.addFinalizer(() => Effect.void)),
  );

const shutdownServer = (
  socketServer: SocketServer,
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
) =>
  pipe(
    Effect.void,
    Effect.andThen(Effect.log('Shutting down server...')),
    Effect.andThen(() => socketServer.dispose()),
    Effect.zipRight(
      Effect.async<void>((resume) => {
        httpServer.close(() => {
          resume(Effect.void);
        });
      }),
    ),
    Effect.andThen(Effect.log('Server shut down')),
  );

const startHttpServer = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  port: number,
  socketServer: SocketServer,
) =>
  pipe(
    Effect.void,
    Effect.zipRight(
      Effect.async<void>((resume) => {
        httpServer.listen(port, () => {
          resume(Effect.void);
        });
      }),
    ),
    Effect.andThen(Effect.log(`Server listening on port ${port}`)),
    Effect.zipRight(
      Effect.addFinalizer(() => shutdownServer(socketServer, httpServer)),
    ),
    Effect.zipRight(Effect.never),
  );

const startSocketServerAndListen = (
  fs: FileSystem.FileSystem,
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  home: Home,
  config: ServerConfig,
) =>
  pipe(
    createSocketServer(fs, httpServer, home, config),
    Effect.tap((socketServer) =>
      Effect.sync(() => socketServer.logConnections()),
    ),
    Effect.andThen((socketServer) =>
      startHttpServer(httpServer, config.port, socketServer),
    ),
  );

const loadAndStartServer = (
  fs: FileSystem.FileSystem,
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  config: ServerConfig,
) =>
  pipe(
    config.homeConfigPath,
    fs.readFileString,
    Effect.andThen(Schema.decode(JsonHomeData)),
    Effect.tap((home) =>
      Effect.log(`Home configuration loaded: ${home.rooms.length} rooms`),
    ),
    Effect.andThen((home) =>
      startSocketServerAndListen(fs, httpServer, home, config),
    ),
  );

/**
 * Runs the Socket.IO server as an Effect application with proper lifecycle management.
 * The server will run until interrupted (e.g., SIGINT/SIGTERM).
 */
export const runServer = (config: ServerConfig) =>
  pipe(
    Effect.void,
    Effect.andThen(() =>
      Effect.all({
        fs: FileSystem.FileSystem,
        // Creates http.Server with Effect lifecycle - closed when scope finalizes
        httpServer: Effect.acquireRelease(
          Effect.sync(() => createServer()),
          (server) =>
            Effect.async<void>((resume) => {
              if (!server.listening) {
                resume(Effect.void);
              } else {
                server.close(() => resume(Effect.void));
              }
            }),
        ),
      }),
    ),
    Effect.andThen(({ fs, httpServer }) =>
      loadAndStartServer(fs, httpServer, config),
    ),
    Effect.scoped,
    Effect.provide(BunFileSystem.layer),
  );
