import { config } from 'dotenv';

config();

import { readFileSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import * as path from 'path';
import { createServer } from 'http';
import { SocketServer } from './app/socket-server';
import debug from 'debug';

const log = debug('app');

const data = readFileSync(
  process.env['HOME_CONFIG_PATH'] || './home.json'
).toString();

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

const httpServer = createServer();

const socketServer = new SocketServer(
  httpServer,
  JSON.parse(data.toString()),
  JSON.parse(initialRoomAdjustments),
  (roomAdjustments) =>
    writeFileSync(roomAdjustmentsPath, JSON.stringify(roomAdjustments)),
  {
    cors: {
      origin: (process.env['CORS_ORIGINS'] || '').split(','),
      methods: ['GET', 'POST', 'OPTIONS'],
    },
  }
);

process.on('SIGINT', function () {
  log('Shutting down');
  socketServer.dispose();
  httpServer.close();
  process.exit();
});

process.on('SIGTERM', function () {
  log('Terminating');
  socketServer.dispose();
  httpServer.close();
  process.exit();
});

const port = process.env['PORT'] || 5123;
log('Listening on port %d', port);

httpServer.listen(port);
