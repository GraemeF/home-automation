import { describe, expect, it } from 'bun:test';
import { pipe, Schema } from 'effect';
import {
  ClimateEntityId,
  decodeTemperature,
} from '@home-automation/deep-heating-types';
import { Subject, toArray, firstValueFrom, take } from 'rxjs';
import {
  getTrvDesiredTargetTemperatures,
  TrvDesiredTargetTemperature,
} from './trvDesiredTargetTemperatures';
import { TrvDecisionPoint } from './trvDecisionPoints';

describe('getTrvDesiredTargetTemperatures', () => {
  const loungeId = pipe(
    'climate.lounge_trv',
    Schema.decodeUnknownSync(ClimateEntityId),
  );
  const kitchenId = pipe(
    'climate.kitchen_trv',
    Schema.decodeUnknownSync(ClimateEntityId),
  );

  it('emits desired temperatures for all TRVs when decision points change', async () => {
    const decisionPoints$ = new Subject<TrvDecisionPoint>();
    const results$ = getTrvDesiredTargetTemperatures(decisionPoints$);

    const resultsPromise = firstValueFrom(results$.pipe(take(2), toArray()));

    // Emit decision points for both TRVs (as would happen when a room updates)
    decisionPoints$.next({
      climateEntityId: loungeId,
      trvTemperature: decodeTemperature(22),
      roomTemperature: decodeTemperature(18),
      roomTargetTemperature: decodeTemperature(20),
      trvMode: 'heat',
    });

    decisionPoints$.next({
      climateEntityId: kitchenId,
      trvTemperature: decodeTemperature(24),
      roomTemperature: decodeTemperature(18),
      roomTargetTemperature: decodeTemperature(20),
      trvMode: 'heat',
    });

    const results = await resultsPromise;

    expect(results).toHaveLength(2);

    // Lounge: target = 20 + 22 - 18 = 24, heating required so rounds up
    const loungeResult = results.find(
      (r) => r.climateEntityId === loungeId,
    ) as TrvDesiredTargetTemperature;
    expect(loungeResult.targetTemperature).toBe(24);

    // Kitchen: target = 20 + 24 - 18 = 26, heating required so rounds up
    const kitchenResult = results.find(
      (r) => r.climateEntityId === kitchenId,
    ) as TrvDesiredTargetTemperature;
    expect(kitchenResult.targetTemperature).toBe(26);
  });

  it('recalculates when TRV temperature changes', async () => {
    const decisionPoints$ = new Subject<TrvDecisionPoint>();
    const results$ = getTrvDesiredTargetTemperatures(decisionPoints$);

    const resultsPromise = firstValueFrom(results$.pipe(take(2), toArray()));

    // Initial decision point
    decisionPoints$.next({
      climateEntityId: loungeId,
      trvTemperature: decodeTemperature(22),
      roomTemperature: decodeTemperature(18),
      roomTargetTemperature: decodeTemperature(20),
      trvMode: 'heat',
    });

    // TRV internal temperature increases (radiator warming up)
    decisionPoints$.next({
      climateEntityId: loungeId,
      trvTemperature: decodeTemperature(24), // was 22
      roomTemperature: decodeTemperature(18),
      roomTargetTemperature: decodeTemperature(20),
      trvMode: 'heat',
    });

    const results = await resultsPromise;

    expect(results).toHaveLength(2);
    // First emission: target = 20 + 22 - 18 = 24
    expect(results[0].targetTemperature).toBe(24);
    // Second emission: target = 20 + 24 - 18 = 26
    expect(results[1].targetTemperature).toBe(26);
  });

  it('clamps target temperature to maximum', async () => {
    const decisionPoints$ = new Subject<TrvDecisionPoint>();
    const results$ = getTrvDesiredTargetTemperatures(decisionPoints$);

    const resultsPromise = firstValueFrom(results$.pipe(take(1), toArray()));

    // Very high offset would exceed maximum
    decisionPoints$.next({
      climateEntityId: kitchenId,
      trvTemperature: decodeTemperature(30),
      roomTemperature: decodeTemperature(10),
      roomTargetTemperature: decodeTemperature(20),
      trvMode: 'heat',
    });

    const results = await resultsPromise;

    // target = 20 + 30 - 10 = 40, but clamped to max 32
    expect(results[0].targetTemperature).toBe(32);
  });

  it('clamps target temperature to minimum', async () => {
    const decisionPoints$ = new Subject<TrvDecisionPoint>();
    const results$ = getTrvDesiredTargetTemperatures(decisionPoints$);

    const resultsPromise = firstValueFrom(results$.pipe(take(1), toArray()));

    // Very low offset would go below minimum
    decisionPoints$.next({
      climateEntityId: loungeId,
      trvTemperature: decodeTemperature(10),
      roomTemperature: decodeTemperature(25),
      roomTargetTemperature: decodeTemperature(18),
      trvMode: 'heat',
    });

    const results = await resultsPromise;

    // target = 18 + 10 - 25 = 3, but clamped to min 7
    expect(results[0].targetTemperature).toBe(7);
  });
});
