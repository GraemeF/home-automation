import { BunContext, BunRuntime } from '@effect/platform-bun';
import { Config, Effect, pipe } from 'effect';
import { tmpdir } from 'os';
import { runServer, ServerConfig } from './server';

const loadConfig = Config.all({
  port: Config.integer('PORT').pipe(Config.withDefault(5123)),
  homeConfigPath: Config.string('HOME_CONFIG_PATH').pipe(
    Config.withDefault('./home.json'),
  ),
  roomAdjustmentsPath: Config.string('ROOM_ADJUSTMENTS_PATH').pipe(
    Config.withDefault(`${tmpdir()}/deep-heating-room-adjustments.json`),
  ),
  websocketPath: Config.string('WEBSOCKET_PATH').pipe(
    Config.withDefault('/ws'),
  ),
}) satisfies Config.Config<ServerConfig>;

const program = pipe(
  loadConfig,
  Effect.andThen(runServer),
  Effect.provide(BunContext.layer),
);

BunRuntime.runMain(program);
