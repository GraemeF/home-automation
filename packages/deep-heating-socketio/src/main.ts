import { readFileSync } from 'fs';
import { createServer } from 'http';
import { SocketServer } from './app/socket-server';

const data = readFileSync(
  process.env['DEEP_HEATING_HOME_CONFIG_FILE'] || './home.json'
);

const httpServer = createServer();

new SocketServer(httpServer, JSON.parse(data.toString()));

httpServer.listen(3000);
