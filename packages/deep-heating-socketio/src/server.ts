import { config } from 'dotenv';

config();

import { FileSystem } from '@effect/platform-node';
import { Schema } from '@effect/schema';
import { Home } from '@home-automation/deep-heating-types';
import { Effect, pipe } from 'effect';
import { readFileSync, writeFileSync } from 'fs';
import { IncomingMessage, Server, ServerResponse } from 'http';
import { tmpdir } from 'os';
import * as path from 'path';
import { SocketServer } from './app/socket-server';

export const handler = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
) => {
  const roomAdjustmentsPath =
    process.env['ROOM_ADJUSTMENTS_PATH'] ||
    path.join(tmpdir(), 'deep-heating-room-adjustments.json');

  const loadAdjustments = () => {
    try {
      return readFileSync(roomAdjustmentsPath).toString();
    } catch (e) {
      return '[]';
    }
  };
  const initialRoomAdjustments = loadAdjustments();

  const JsonHomeData = Schema.ParseJson.pipe(Schema.compose(Home));

  const readDataFromFile = (fs: FileSystem.FileSystem) =>
    pipe(
      process.env['HOME_CONFIG_PATH'] || './home.json',
      fs.readFileString,
      Effect.flatMap(Schema.decode(JsonHomeData)),
    );

  return pipe(
    FileSystem.FileSystem,
    Effect.flatMap((fs) => readDataFromFile(fs)),
    Effect.tap((data) => Effect.log(data)),
    Effect.map(
      (data) =>
        new SocketServer(
          httpServer,
          data,
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
        ),
    ),
    Effect.tap((server) => server.logConnections()),
    Effect.tap(() => Effect.log('Socket.io server started')),
    Effect.provide(FileSystem.layer),
    Effect.runPromise,
  );
};
