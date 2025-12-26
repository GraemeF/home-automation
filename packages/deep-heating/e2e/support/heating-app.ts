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
      Effect.promise(() =>
        app.page.getByRole('button', { name: /pop.?out/i }).click(),
      ),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const cancelPopOut = (
  app: HeatingApp,
): Effect.Effect<HeatingApp, TestError> =>
  pipe(
    Effect.promise(() =>
      app.page.getByRole('button', { name: /cancel/i }).click(),
    ),
    Effect.map(() => app),
    Effect.mapError((e) => new TestError(String(e))),
  );

export const expectAllRoomsAt =
  (temperature: number) =>
  (app: HeatingApp): Effect.Effect<HeatingApp, TestError> =>
    pipe(
      Effect.promise(async () => {
        // User sees target temperatures displayed for each room
        const targetTemps = app.page.getByLabel(/target/i);
        const count = await targetTemps.count();
        // Must have at least one room showing target temperature
        expect(count).toBeGreaterThan(0);
        for (let i = 0; i < count; i++) {
          await expect(targetTemps.nth(i)).toContainText(String(temperature));
        }
      }),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const expectPopOutOverlay =
  (_options: { readonly showsCancelOnly: boolean }) =>
  (app: HeatingApp): Effect.Effect<HeatingApp, TestError> =>
    pipe(
      Effect.promise(async () => {
        // User sees a dialog indicating they're popping out
        await expect(
          app.page.getByRole('dialog', { name: /pop.?out/i }),
        ).toBeVisible();
        await expect(
          app.page.getByRole('button', { name: /cancel/i }),
        ).toBeVisible();
      }),
      Effect.map(() => app),
      Effect.mapError((e) => new TestError(String(e))),
    );

export const expectNormalSchedule = (
  app: HeatingApp,
): Effect.Effect<HeatingApp, TestError> =>
  pipe(
    Effect.promise(async () => {
      // Pop-out dialog should no longer be visible
      await expect(
        app.page.getByRole('dialog', { name: /pop.?out/i }),
      ).not.toBeVisible();
    }),
    Effect.map(() => app),
    Effect.mapError((e) => new TestError(String(e))),
  );
