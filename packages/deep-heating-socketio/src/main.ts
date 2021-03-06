import { config } from 'dotenv';

config();

import { readFileSync } from 'fs';
import { createServer } from 'http';
import { SocketServer } from './app/socket-server';
import debug from 'debug';

const log = debug('app');

const data = readFileSync(
  process.env['HOME_CONFIG_PATH'] || './home.json'
).toString();

const httpServer = createServer();

const socketServer = new SocketServer(httpServer, JSON.parse(data.toString()), {
  cors: {
    origin: (process.env['CORS_ORIGINS'] || '').split(','),
    methods: ['GET', 'POST', 'OPTIONS'],
  },
});

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
