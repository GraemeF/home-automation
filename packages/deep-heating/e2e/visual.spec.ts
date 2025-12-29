import { test } from '@playwright/test';
import { Effect, pipe } from 'effect';
import * as HeatingApp from './support/heating-app';

test.describe('Visual Regression', () => {
  test('dashboard matches baseline snapshot', async ({ page }) => {
    await Effect.runPromise(
      pipe(
        HeatingApp.make(page),
        Effect.flatMap(HeatingApp.captureVisualSnapshot('dashboard')),
      ),
    );
  });
});
