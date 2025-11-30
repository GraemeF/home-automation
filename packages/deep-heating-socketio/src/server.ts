import { FileSystem } from '@effect/platform';
import { BunFileSystem } from '@effect/platform-bun';
import { Effect, pipe, Schema } from 'effect';
import { Home } from '@home-automation/deep-heating-types';
import { readFileSync, writeFileSync } from 'fs';
import { IncomingMessage, Server, ServerResponse } from 'http';
import { tmpdir } from 'os';
import * as path from 'path';
import { SocketServer } from './app/socket-server';

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
  roomAdjustmentsPath: string,
) => {
  const initialRoomAdjustments = loadRoomAdjustments(roomAdjustmentsPath);
  return new SocketServer(
    httpServer,
    home,
    JSON.parse(initialRoomAdjustments),
    (roomAdjustments) =>
      writeFileSync(roomAdjustmentsPath, JSON.stringify(roomAdjustments)),
    {
      path: process.env['SOCKETIO_PATH'] || '/socket.io',
      cors: {
        origin: (process.env['CORS_ORIGINS'] || '').split(','),
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
  port: number,
  roomAdjustmentsPath: string,
) => {
  const configPath = process.env['HOME_CONFIG_PATH'] || './home.json';
  return pipe(
    configPath,
    fs.readFileString,
    Effect.andThen(Schema.decode(JsonHomeData)),
    Effect.tap((home) =>
      Effect.log(`Home configuration loaded: ${home.rooms.length} rooms`),
    ),
    Effect.andThen((home) => {
      const socketServer = createSocketServer(
        httpServer,
        home,
        roomAdjustmentsPath,
      );
      socketServer.logConnections();
      return startHttpServer(httpServer, port, socketServer);
    }),
  );
};

/**
 * Runs the Socket.IO server as an Effect application with proper lifecycle management.
 * The server will run until interrupted (e.g., SIGINT/SIGTERM).
 */
export const runServer = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
  port: number,
) => {
  const roomAdjustmentsPath =
    process.env['ROOM_ADJUSTMENTS_PATH'] ||
    path.join(tmpdir(), 'deep-heating-room-adjustments.json');

  return pipe(
    FileSystem.FileSystem,
    Effect.andThen((fs) =>
      loadAndStartServer(fs, httpServer, port, roomAdjustmentsPath),
    ),
    Effect.scoped,
    Effect.provide(BunFileSystem.layer),
  );
};
