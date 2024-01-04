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

export const handle = (
  httpServer: Server<typeof IncomingMessage, typeof ServerResponse>,
) => {
  const roomAdjustmentsPath =
    process.env['ROOM_ADJUSTMENTS_PATH'] ||
    path.join(tmpdir(), 'deep-heating-room-adjustments.json');

  const loadAdjustments = () => {
    try {
      return readFileSync(roomAdjustmentsPath).toString();
    } catch (e) {
      console.error(e);
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

  pipe(
    FileSystem.FileSystem,
    Effect.flatMap((fs) => readDataFromFile(fs)),
    Effect.map(
      (data) =>
        new SocketServer(
          httpServer,
          data,
          JSON.parse(initialRoomAdjustments),
          (roomAdjustments) =>
            writeFileSync(roomAdjustmentsPath, JSON.stringify(roomAdjustments)),
          {
            cors: {
              origin: (process.env['CORS_ORIGINS'] || '').split(','),
              methods: ['GET', 'POST', 'OPTIONS'],
            },
          },
        ),
    ),
    Effect.provide(FileSystem.layer),
    Effect.runPromise,
  );
};
