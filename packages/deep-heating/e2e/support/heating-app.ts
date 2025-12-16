import { Context, Effect, Layer, pipe } from 'effect';
import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';
import type { ReturnTime } from './return-time';

export class TestError extends Error {
  readonly _tag = 'TestError';
}

interface PopOutConfig {
  readonly popOutTemperature: number;
}

export const PopOutConfig = Context.GenericTag<PopOutConfig>('PopOutConfig');

export const TestConfigLayer = (
  config: PopOutConfig,
): Layer.Layer<PopOutConfig> => Layer.succeed(PopOutConfig, config);

interface HeatingApp {
  readonly page: Page;
}

export const make = (page: Page): Effect.Effect<HeatingApp> =>
  pipe(
    Effect.succeed({ page }),
    Effect.tap(() =>
      Effect.promise(() => page.goto('/', { waitUntil: 'networkidle' })),
    ),
  );

export const initiatePopOut =
  (_returnTime: ReturnTime) =>
  (app: HeatingApp): Effect.Effect<HeatingApp, TestError> =>
    pipe(
      Effect.promise(() => app.page.getByTestId('pop-out-button').click()),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const cancelPopOut = (
  app: HeatingApp,
): Effect.Effect<HeatingApp, TestError> =>
  pipe(
    Effect.promise(() => app.page.getByTestId('cancel-pop-out').click()),
    Effect.map(() => app),
    Effect.mapError((e) => new TestError(String(e))),
  );

export const expectAllRoomsAt =
  (temperature: number) =>
  (app: HeatingApp): Effect.Effect<HeatingApp, TestError> =>
    pipe(
      Effect.promise(async () => {
        const rooms = app.page.getByTestId('room-temperature');
        await expect(rooms).toContainText(String(temperature));
      }),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const expectPopOutOverlay =
  (_options: { readonly showsCancelOnly: boolean }) =>
  (app: HeatingApp): Effect.Effect<HeatingApp, TestError> =>
    pipe(
      Effect.promise(async () => {
        await expect(app.page.getByTestId('pop-out-overlay')).toBeVisible();
        await expect(app.page.getByTestId('cancel-pop-out')).toBeVisible();
      }),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const expectNormalSchedule = (
  app: HeatingApp,
): Effect.Effect<HeatingApp, TestError> =>
  pipe(
    Effect.promise(async () => {
      await expect(app.page.getByTestId('pop-out-overlay')).not.toBeVisible();
    }),
    Effect.map(() => app),
    Effect.mapError((e) => new TestError(String(e))),
  );
