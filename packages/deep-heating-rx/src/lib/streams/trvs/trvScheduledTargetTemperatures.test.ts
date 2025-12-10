import { describe, expect, it } from '@codeforbreakfast/bun-test-effect';
import { Array, Effect, pipe, Schema, Stream } from 'effect';
import {
  ClimateEntityId,
  TrvWeekHeatingSchedule,
  WeekSchedule,
} from '@home-automation/deep-heating-types';
import { observableToStream } from '@home-automation/rxx';
import { Subject, firstValueFrom, take, timeout, toArray } from 'rxjs';
import { getTrvScheduledTargetTemperatures } from './trvScheduledTargetTemperatures';

const decodeClimateEntityId = Schema.decodeSync(ClimateEntityId);
const decodeWeekSchedule = Schema.decodeSync(WeekSchedule);

const createTrvSchedule = (
  trvId: string,
  temp: number,
): TrvWeekHeatingSchedule => ({
  climateEntityId: decodeClimateEntityId(trvId),
  schedule: decodeWeekSchedule({
    monday: { '00:00': temp },
    tuesday: { '00:00': temp },
    wednesday: { '00:00': temp },
    thursday: { '00:00': temp },
    friday: { '00:00': temp },
    saturday: { '00:00': temp },
    sunday: { '00:00': temp },
  }),
});

describe('getTrvScheduledTargetTemperatures', () => {
  it('emits scheduled temperatures for ALL TRVs, not just the latest', async () => {
    const trvHiveHeatingSchedule$ = new Subject<TrvWeekHeatingSchedule>();

    const scheduledTemps$ = getTrvScheduledTargetTemperatures(
      trvHiveHeatingSchedule$,
    );

    // We expect to receive scheduled temps for BOTH TRVs
    const resultsPromise = firstValueFrom(
      scheduledTemps$.pipe(take(2), toArray(), timeout(2000)),
    );

    // Emit schedules for two different TRVs
    trvHiveHeatingSchedule$.next(createTrvSchedule('climate.trv_living', 20));
    trvHiveHeatingSchedule$.next(createTrvSchedule('climate.trv_bedroom', 18));

    const results = await resultsPromise;

    expect(results).toHaveLength(2);

    const livingResult = results.find(
      (r) => r.climateEntityId === 'climate.trv_living',
    );
    const bedroomResult = results.find(
      (r) => r.climateEntityId === 'climate.trv_bedroom',
    );

    expect(livingResult).toBeDefined();
    expect(bedroomResult).toBeDefined();
    expect(livingResult?.scheduledTargetTemperature).toBe(20);
    expect(bedroomResult?.scheduledTargetTemperature).toBe(18);
  });

  // This test specifically verifies the bug: when the timer fires,
  // ALL TRVs should get new scheduled temperatures, not just the
  // last one that emitted a schedule update.
  //
  // Current broken behavior: only last TRV gets scheduled temp on timer
  // Expected behavior: all TRVs get scheduled temp on timer
  it.effect(
    'emits for ALL stored TRVs when timer fires, not just the latest one',
    () => {
      const trvHiveHeatingSchedule$ = new Subject<TrvWeekHeatingSchedule>();

      const scheduledTemps$ = getTrvScheduledTargetTemperatures(
        trvHiveHeatingSchedule$,
      );

      // Emit schedules for two TRVs after stream subscription is established
      setTimeout(() => {
        trvHiveHeatingSchedule$.next(
          createTrvSchedule('climate.trv_living', 20),
        );
        trvHiveHeatingSchedule$.next(
          createTrvSchedule('climate.trv_bedroom', 18),
        );
      }, 10);

      return pipe(
        scheduledTemps$,
        observableToStream,
        Stream.take(2),
        Stream.runCollect,
        Effect.map(Array.fromIterable),
        Effect.map((emissions) => {
          const livingEmissions = emissions.filter(
            (e) => e.climateEntityId === 'climate.trv_living',
          );
          const bedroomEmissions = emissions.filter(
            (e) => e.climateEntityId === 'climate.trv_bedroom',
          );

          // Both TRVs should have received at least one scheduled temp emission
          expect(livingEmissions.length).toBeGreaterThanOrEqual(1);
          expect(bedroomEmissions.length).toBeGreaterThanOrEqual(1);
        }),
      );
    },
  );
});
