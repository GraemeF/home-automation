import { test } from '@playwright/test';
import { Duration, Effect, pipe } from 'effect';
import * as HeatingApp from './support/heating-app';
import * as ReturnTime from './support/return-time';

test.describe.skip('Popping Out', () => {
  const popOutTemperature = 10;

  test('user can pop out and cancel to return to normal schedule', async ({
    page,
  }) => {
    await Effect.runPromise(
      pipe(
        HeatingApp.make(page),
        Effect.flatMap(
          HeatingApp.initiatePopOut(ReturnTime.duration(Duration.hours(2))),
        ),
        Effect.flatMap(HeatingApp.expectAllRoomsAt(popOutTemperature)),
        Effect.flatMap(
          HeatingApp.expectPopOutOverlay({ showsCancelOnly: true }),
        ),
        Effect.flatMap(HeatingApp.cancelPopOut),
        Effect.flatMap(HeatingApp.expectNormalSchedule),
      ).pipe(Effect.provide(HeatingApp.TestConfigLayer({ popOutTemperature }))),
    );
  });
});
