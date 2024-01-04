import { config } from 'dotenv';

config();

import debug from 'debug';
import { createServer } from 'http';
import { handler } from './server';

const log = debug('app');

const httpServer = createServer();

handler(httpServer);

const port = process.env['PORT'] || 5123;

httpServer.listen(port);

log('Listening on port %d', port);
