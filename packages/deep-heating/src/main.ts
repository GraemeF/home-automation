import express from 'express';
import { createServer } from 'http';
import { handler as frontend } from '../../../dist/packages/deep-heating-web/handler.js';
import { handler as backend } from '../../deep-heating-socketio/src/server';

const app = express();
const server = createServer(app);

// handle socket.io connections
await backend(server);

// let SvelteKit handle everything else, including serving prerendered pages and static assets
app.use(frontend);

const port = process.env['PORT'] || 3000;

app.listen(port, () => {
  console.log('listening on port', port);
});
