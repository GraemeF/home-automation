import { FileSystem } from '@effect/platform';
import { BunFileSystem } from '@effect/platform-bun';
import { Schema } from 'effect';
import { Home } from '@home-automation/deep-heating-types';
import { Effect } from 'effect';
import { readFileSync, writeFileSync } from 'fs';
import { IncomingMessage, Server, ServerResponse } from 'http';
import { tmpdir } from 'os';
import * as path from 'path';
import { SocketServer } from './app/socket-server';

const JsonHomeData = Schema.parseJson(Home);

const readHomeConfig = (fs: FileSystem.FileSystem) => {
  const configPath = process.env['HOME_CONFIG_PATH'] || './home.json';
  return fs
    .readFileString(configPath)
    .pipe(Effect.flatMap(Schema.decode(JsonHomeData)));
};

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

  return Effect.gen(function* () {
    const fs = yield* FileSystem.FileSystem;
    const home = yield* readHomeConfig(fs);

    yield* Effect.log(`Home configuration loaded: ${home.rooms.length} rooms`);

    const socketServer = createSocketServer(
      httpServer,
      home,
      roomAdjustmentsPath,
    );
    socketServer.logConnections();

    // Start HTTP server
    yield* Effect.async<void>((resume) => {
      httpServer.listen(port, () => {
        resume(Effect.void);
      });
    });

    yield* Effect.log(`Server listening on port ${port}`);

    // Add finalizer for graceful shutdown
    yield* Effect.addFinalizer(() =>
      Effect.gen(function* () {
        yield* Effect.log('Shutting down server...');
        socketServer.dispose();
        yield* Effect.async<void>((resume) => {
          httpServer.close(() => {
            resume(Effect.void);
          });
        });
        yield* Effect.log('Server shut down');
      }),
    );

    // Keep the server running forever until interrupted
    yield* Effect.never;
  }).pipe(Effect.scoped, Effect.provide(BunFileSystem.layer));
};
