import { FileSystem } from '@effect/platform';
import { BunFileSystem } from '@effect/platform-bun';
import { Effect, pipe, Schema } from 'effect';
import { Home } from '@home-automation/deep-heating-types';
// eslint-disable-next-line effect/prefer-effect-platform -- socket.io server being migrated away
import { readFileSync, writeFileSync } from 'fs';
// eslint-disable-next-line effect/prefer-effect-platform -- socket.io server being migrated away
import { IncomingMessage, Server, ServerResponse } from 'http';
import { SocketServer } from './app/socket-server';

export interface ServerConfig {
  readonly port: number;
  readonly homeConfigPath: string;
  readonly roomAdjustmentsPath: string;
  readonly socketioPath: string;
  readonly corsOrigins: readonly string[];
}

const JsonHomeData = Schema.parseJson(Home);

const loadRoomAdjustments = (roomAdjustmentsPath: string): string => {
  try {
    return readFileSync(roomAdjustmentsPath).toString();
  } catch {
    return '[]';
  }
};

const createSocketServer = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  home: Home,
  config: ServerConfig,
) => {
  const initialRoomAdjustments = loadRoomAdjustments(
    config.roomAdjustmentsPath,
  );
  return new SocketServer(
    httpServer,
    home,
    JSON.parse(initialRoomAdjustments),
    (roomAdjustments) =>
      writeFileSync(
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
};

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
    Effect.andThen((home) => {
      const socketServer = createSocketServer(httpServer, home, config);
      socketServer.logConnections();
      return startHttpServer(httpServer, config.port, socketServer);
    }),
  );

/**
 * Runs the Socket.IO server as an Effect application with proper lifecycle management.
 * The server will run until interrupted (e.g., SIGINT/SIGTERM).
 */
export const runServer = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  config: ServerConfig,
) =>
  pipe(
    FileSystem.FileSystem,
    Effect.andThen((fs) => loadAndStartServer(fs, httpServer, config)),
    Effect.scoped,
    Effect.provide(BunFileSystem.layer),
  );
