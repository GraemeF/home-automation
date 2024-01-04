import { config } from 'dotenv';

config();

import debug from 'debug';
import { createServer } from 'http';
import { handle } from './server';

const log = debug('app');

const httpServer = createServer();

handle(httpServer);

const port = process.env['PORT'] || 5123;

httpServer.listen(port);

log('Listening on port %d', port);
