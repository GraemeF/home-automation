// eslint-disable-next-line @nx/enforce-module-boundaries
import { handler as backend } from '@home-automation/deep-heating-socketio';
import express from 'express';
import { createServer } from 'http';
import { handler as frontend } from '../../../dist/packages/deep-heating-web/handler.js';

const app = express();
const server = createServer(app);

// handle socket.io connections
await backend(server);

// let SvelteKit handle everything else, including serving prerendered pages and static assets
app.use(frontend);

const port = process.env['PORT'] || 3000;

server.listen(port, () => {
  console.log('listening on port', port);
});
