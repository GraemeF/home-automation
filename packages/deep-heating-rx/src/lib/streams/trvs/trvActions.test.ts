import { describe, expect, it } from 'bun:test';
import { Either, pipe, Schema } from 'effect';
import {
  ClimateEntityId,
  ClimateTemperatureReading,
  decodeTemperature,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { Subject, firstValueFrom, timeout, take, toArray } from 'rxjs';
import { determineAction, getTrvActions } from './trvActions';
import { TrvDesiredTargetTemperature } from './trvDesiredTargetTemperatures';

describe('TRV action', () => {
  const daytime: DateTime = DateTime.fromISO('2020-01-01T12:00Z');
  const trvId = pipe(
    'climate.the_trv',
    Schema.decodeUnknownSync(ClimateEntityId),
  );
  it('returns Either.left when climateEntityIds mismatch', () => {
    const result = determineAction(
      {
        climateEntityId: trvId,
        targetTemperature: decodeTemperature(20),
      },
      {
        climateEntityId: pipe(
          'climate.other_trv',
          Schema.decodeUnknownSync(ClimateEntityId),
        ),
        mode: 'heat',
        source: 'Device',
        targetTemperature: decodeTemperature(18),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: decodeTemperature(10),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(18),
      },
    );

    expect(Either.isLeft(result)).toBe(true);
    Either.match(result, {
      onLeft: (error) => {
        expect(error).toMatchObject({ _tag: 'MismatchedClimateEntityIds' });
      },
      onRight: () => {
        expect.unreachable('Expected Either.left');
      },
    });
  });

  it('returns Either.right(null) when TRV is off', () => {
    const result = determineAction(
      {
        climateEntityId: trvId,
        targetTemperature: decodeTemperature(20),
      },
      {
        climateEntityId: trvId,
        mode: 'off',
        source: 'Device',
        targetTemperature: decodeTemperature(7),
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          time: daytime.toJSDate(),
          temperature: decodeTemperature(10),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(18),
      },
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBeNull();
    }
  });

  it('returns Either.right(action) when action needed', () => {
    const result = determineAction(
      {
        targetTemperature: decodeTemperature(23),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(18.5),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(21),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(18),
      },
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toStrictEqual({
        mode: 'heat',
        targetTemperature: 23,
        climateEntityId: trvId,
      });
    }
  });

  it('returns Either.right(action) when mode needs to change from auto to heat', () => {
    const result = determineAction(
      {
        targetTemperature: decodeTemperature(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'auto',
        targetTemperature: decodeTemperature(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(23),
      },
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toStrictEqual({
        mode: 'heat',
        targetTemperature: 18.5,
        climateEntityId: trvId,
      });
    }
  });

  it('returns Either.right(action) when target temperature needs to change', () => {
    const result = determineAction(
      {
        targetTemperature: decodeTemperature(18.5),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(23),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18.5),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(23),
      },
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toStrictEqual({
        mode: 'heat',
        targetTemperature: 18.5,
        climateEntityId: trvId,
      });
    }
  });

  it('returns Either.right(null) when no action needed (mode and temp match)', () => {
    const result = determineAction(
      {
        targetTemperature: decodeTemperature(20),
        climateEntityId: trvId,
      },
      {
        climateEntityId: trvId,
        mode: 'heat',
        targetTemperature: decodeTemperature(20),
        source: 'Device',
      },
      {
        climateEntityId: trvId,
        temperatureReading: {
          temperature: decodeTemperature(18),
          time: daytime.toJSDate(),
        },
      },
      {
        climateEntityId: trvId,
        scheduledTargetTemperature: decodeTemperature(20),
      },
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBeNull();
    }
  });
});

describe('getTrvActions pipeline', () => {
  const decodeTrvId = Schema.decodeSync(ClimateEntityId);
  const daytime = DateTime.fromISO('2020-01-01T12:00Z');

  const createTrvControlState = (
    trvId: ClimateEntityId,
    targetTemp: number,
  ): TrvControlState => ({
    climateEntityId: trvId,
    mode: 'heat',
    targetTemperature: decodeTemperature(targetTemp),
    source: 'Device',
  });

  const createTrvTemperature = (
    trvId: ClimateEntityId,
    temp: number,
  ): ClimateTemperatureReading => ({
    climateEntityId: trvId,
    temperatureReading: {
      temperature: decodeTemperature(temp),
      time: daytime.toJSDate(),
    },
  });

  const createTrvDesiredTemp = (
    trvId: ClimateEntityId,
    targetTemp: number,
  ): TrvDesiredTargetTemperature => ({
    climateEntityId: trvId,
    targetTemperature: decodeTemperature(targetTemp),
  });

  const createTrvScheduledTemp = (
    trvId: ClimateEntityId,
    scheduledTemp: number,
  ): TrvScheduledTargetTemperature => ({
    climateEntityId: trvId,
    scheduledTargetTemperature: decodeTemperature(scheduledTemp),
  });

  it('should generate action when desired temp differs from current', async () => {
    const trvId = decodeTrvId('climate.lounge_radiator');

    const trvIds$ = new Subject<readonly ClimateEntityId[]>();
    const trvDesiredTargetTemperatures$ =
      new Subject<TrvDesiredTargetTemperature>();
    const trvControlStates$ = new Subject<TrvControlState>();
    const trvTemperatures$ = new Subject<ClimateTemperatureReading>();
    const trvScheduledTargetTemperatures$ =
      new Subject<TrvScheduledTargetTemperature>();

    const actions$ = getTrvActions(
      trvIds$,
      trvDesiredTargetTemperatures$,
      trvControlStates$,
      trvTemperatures$,
      trvScheduledTargetTemperatures$,
    );

    const actionPromise = firstValueFrom(actions$.pipe(timeout(1000)));

    // Emit TRV IDs first
    trvIds$.next([trvId]);

    // Emit all required data for the TRV
    trvControlStates$.next(createTrvControlState(trvId, 15)); // Current: 15
    trvTemperatures$.next(createTrvTemperature(trvId, 16));
    trvScheduledTargetTemperatures$.next(createTrvScheduledTemp(trvId, 20));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trvId, 20)); // Desired: 20

    const action = await actionPromise;
    expect(action.climateEntityId).toBe(trvId);
    expect(action.targetTemperature).toBe(20);
    expect(action.mode).toBe('heat');
  });

  it('should NOT generate action when desired temp equals current', async () => {
    const trvId = decodeTrvId('climate.lounge_radiator');

    const trvIds$ = new Subject<readonly ClimateEntityId[]>();
    const trvDesiredTargetTemperatures$ =
      new Subject<TrvDesiredTargetTemperature>();
    const trvControlStates$ = new Subject<TrvControlState>();
    const trvTemperatures$ = new Subject<ClimateTemperatureReading>();
    const trvScheduledTargetTemperatures$ =
      new Subject<TrvScheduledTargetTemperature>();

    const actions$ = getTrvActions(
      trvIds$,
      trvDesiredTargetTemperatures$,
      trvControlStates$,
      trvTemperatures$,
      trvScheduledTargetTemperatures$,
    );

    const collector = { count: 0 };
    const sub = actions$.subscribe(() => {
      collector.count += 1;
    });

    // Emit TRV IDs first
    trvIds$.next([trvId]);

    // Emit all required data - but desired equals current
    trvControlStates$.next(createTrvControlState(trvId, 20)); // Current: 20
    trvTemperatures$.next(createTrvTemperature(trvId, 16));
    trvScheduledTargetTemperatures$.next(createTrvScheduledTemp(trvId, 20));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trvId, 20)); // Desired: 20

    // Wait a bit to ensure no action is emitted
    await new Promise((resolve) => setTimeout(resolve, 100));

    sub.unsubscribe();
    expect(collector.count).toBe(0);
  });

  it('should block if trvScheduledTargetTemperatures never emits', async () => {
    const trvId = decodeTrvId('climate.lounge_radiator');

    const trvIds$ = new Subject<readonly ClimateEntityId[]>();
    const trvDesiredTargetTemperatures$ =
      new Subject<TrvDesiredTargetTemperature>();
    const trvControlStates$ = new Subject<TrvControlState>();
    const trvTemperatures$ = new Subject<ClimateTemperatureReading>();
    const trvScheduledTargetTemperatures$ =
      new Subject<TrvScheduledTargetTemperature>();

    const actions$ = getTrvActions(
      trvIds$,
      trvDesiredTargetTemperatures$,
      trvControlStates$,
      trvTemperatures$,
      trvScheduledTargetTemperatures$,
    );

    const collector = { count: 0 };
    const sub = actions$.subscribe(() => {
      collector.count += 1;
    });

    // Emit TRV IDs first
    trvIds$.next([trvId]);

    // Emit all EXCEPT trvScheduledTargetTemperatures
    trvControlStates$.next(createTrvControlState(trvId, 15));
    trvTemperatures$.next(createTrvTemperature(trvId, 16));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trvId, 20));
    // NOTE: NOT emitting trvScheduledTargetTemperatures$

    // Wait to see if action is emitted (it shouldn't be)
    await new Promise((resolve) => setTimeout(resolve, 100));

    sub.unsubscribe();
    // This demonstrates the blocking behavior - no action generated
    // because combineLatest requires all streams to emit
    expect(collector.count).toBe(0);
  });

  it('should handle multiple TRVs independently - one blocked should not block another', async () => {
    const trv1 = decodeTrvId('climate.lounge_radiator');
    const trv2 = decodeTrvId('climate.kitchen_radiator');

    const trvIds$ = new Subject<readonly ClimateEntityId[]>();
    const trvDesiredTargetTemperatures$ =
      new Subject<TrvDesiredTargetTemperature>();
    const trvControlStates$ = new Subject<TrvControlState>();
    const trvTemperatures$ = new Subject<ClimateTemperatureReading>();
    const trvScheduledTargetTemperatures$ =
      new Subject<TrvScheduledTargetTemperature>();

    const actions$ = getTrvActions(
      trvIds$,
      trvDesiredTargetTemperatures$,
      trvControlStates$,
      trvTemperatures$,
      trvScheduledTargetTemperatures$,
    );

    const actionPromise = firstValueFrom(actions$.pipe(timeout(1000)));

    // Emit both TRV IDs
    trvIds$.next([trv1, trv2]);

    // Emit complete data for TRV1 only
    trvControlStates$.next(createTrvControlState(trv1, 15));
    trvTemperatures$.next(createTrvTemperature(trv1, 16));
    trvScheduledTargetTemperatures$.next(createTrvScheduledTemp(trv1, 20));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trv1, 20));

    // TRV2 has partial data - missing trvScheduledTargetTemperatures
    trvControlStates$.next(createTrvControlState(trv2, 15));
    trvTemperatures$.next(createTrvTemperature(trv2, 19));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trv2, 23));
    // NOT emitting trvScheduledTargetTemperatures for TRV2

    // TRV1 should still get an action even though TRV2 is incomplete
    const action = await actionPromise;
    expect(action.climateEntityId).toBe(trv1);
    expect(action.targetTemperature).toBe(20);
  });

  it('should emit action for TRV2 when its scheduled temp arrives late', async () => {
    const trv1 = decodeTrvId('climate.lounge_radiator');
    const trv2 = decodeTrvId('climate.kitchen_radiator');

    const trvIds$ = new Subject<readonly ClimateEntityId[]>();
    const trvDesiredTargetTemperatures$ =
      new Subject<TrvDesiredTargetTemperature>();
    const trvControlStates$ = new Subject<TrvControlState>();
    const trvTemperatures$ = new Subject<ClimateTemperatureReading>();
    const trvScheduledTargetTemperatures$ =
      new Subject<TrvScheduledTargetTemperature>();

    const actions$ = getTrvActions(
      trvIds$,
      trvDesiredTargetTemperatures$,
      trvControlStates$,
      trvTemperatures$,
      trvScheduledTargetTemperatures$,
    );

    const actionsPromise = firstValueFrom(
      actions$.pipe(take(2), toArray(), timeout(1000)),
    );

    // Emit both TRV IDs
    trvIds$.next([trv1, trv2]);

    // Emit complete data for TRV1
    trvControlStates$.next(createTrvControlState(trv1, 15));
    trvTemperatures$.next(createTrvTemperature(trv1, 16));
    trvScheduledTargetTemperatures$.next(createTrvScheduledTemp(trv1, 20));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trv1, 20));

    // Emit partial data for TRV2
    trvControlStates$.next(createTrvControlState(trv2, 15));
    trvTemperatures$.next(createTrvTemperature(trv2, 19));
    trvDesiredTargetTemperatures$.next(createTrvDesiredTemp(trv2, 23));

    // Simulate delay, then emit the missing scheduled temp for TRV2
    await new Promise((resolve) => setTimeout(resolve, 50));
    trvScheduledTargetTemperatures$.next(createTrvScheduledTemp(trv2, 20));

    const actions = await actionsPromise;
    expect(actions).toHaveLength(2);

    const trv1Action = actions.find((a) => a.climateEntityId === trv1);
    const trv2Action = actions.find((a) => a.climateEntityId === trv2);

    expect(trv1Action?.targetTemperature).toBe(20);
    expect(trv2Action?.targetTemperature).toBe(23);
  });
});
