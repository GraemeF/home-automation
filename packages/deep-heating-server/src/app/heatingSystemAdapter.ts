import {
  ClimateAction,
  HeatingSystem,
} from '@home-automation/deep-heating-types';
import type { HeatingSystemStreams } from '@home-automation/deep-heating-rx';
import { Context, Effect } from 'effect';
import { pipe } from 'effect';
import { Subject, Subscription } from 'rxjs';
import { debounceTime, groupBy, mergeMap } from 'rxjs/operators';

interface HeatingSystemAdapterResult {
  readonly streams: HeatingSystemStreams;
  readonly cleanup: () => void;
}

/**
 * Creates a bridge adapter from HeatingSystem service to HeatingSystemStreams.
 *
 * The adapter:
 * - Exposes HeatingSystem observables as HeatingSystemStreams
 * - Applies debouncing to TRV and heating actions (5s debounce)
 * - Groups TRV actions by entity ID for per-device debouncing
 */
export const createHeatingSystemAdapter = (
  heatingSystem: Context.Tag.Service<typeof HeatingSystem>,
): HeatingSystemAdapterResult => {
  const trvActionSubject = new Subject<ClimateAction>();
  const heatingActionSubject = new Subject<ClimateAction>();
  const subscriptions: readonly Subscription[] = [];

  // TRV actions: 5s debounce per entity (prevents rapid API calls)
  const trvSubscription = trvActionSubject
    .pipe(
      groupBy((x) => x.climateEntityId),
      mergeMap((group) => group.pipe(debounceTime(5000))),
    )
    .subscribe((action) => {
      // Run both mode and temperature - order doesn't matter, HA handles atomically
      Effect.runFork(
        pipe(
          Effect.all(
            [
              heatingSystem.setTrvMode(action.climateEntityId, action.mode),
              heatingSystem.setTrvTemperature(
                action.climateEntityId,
                action.targetTemperature,
              ),
            ],
            { concurrency: 'unbounded' },
          ),
          Effect.catchAllCause((cause) => {
            return Effect.sync(() => {
              console.error('TRV action failed:', cause);
            });
          }),
        ),
      );
    });

  // Heating actions: 5s flat debounce (single heating entity)
  const heatingSubscription = heatingActionSubject
    .pipe(debounceTime(5000))
    .subscribe((action) => {
      Effect.runFork(
        pipe(
          Effect.all(
            [
              heatingSystem.setTrvMode(action.climateEntityId, action.mode),
              heatingSystem.setTrvTemperature(
                action.climateEntityId,
                action.targetTemperature,
              ),
            ],
            { concurrency: 'unbounded' },
          ),
          Effect.catchAllCause((cause) => {
            return Effect.sync(() => {
              console.error('Heating action failed:', cause);
            });
          }),
        ),
      );
    });

  const allSubscriptions = [
    ...subscriptions,
    trvSubscription,
    heatingSubscription,
  ];

  return {
    streams: {
      trvUpdates$: heatingSystem.trvUpdates,
      heatingUpdates$: heatingSystem.heatingUpdates,
      temperatureReadings$: heatingSystem.temperatureReadings,
      sleepModeEvents$: heatingSystem.sleepModeEvents,
      applyTrvAction: (action: ClimateAction) => {
        trvActionSubject.next(action);
      },
      applyHeatingAction: (action: ClimateAction) => {
        heatingActionSubject.next(action);
      },
    },
    cleanup: () => {
      allSubscriptions.forEach((s) => {
        s.unsubscribe();
      });
    },
  };
};
