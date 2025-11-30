import { config } from 'dotenv';

config();

import { BunContext, BunRuntime } from '@effect/platform-bun';
import { Effect, pipe } from 'effect';
import { createServer } from 'http';
import { runServer } from './server';

const port = Number(process.env['PORT']) || 5123;
const httpServer = createServer();

const program = pipe(
  runServer(httpServer, port),
  Effect.provide(BunContext.layer),
);

BunRuntime.runMain(program);
