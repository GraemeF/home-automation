import { Schema, pipe } from 'effect';
import {
  ClimateEntityId,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable, combineLatest, timer } from 'rxjs';
import { map, share } from 'rxjs/operators';
import {
  MaximumTrvTargetTemperature,
  MinimumTrvTargetTemperature,
  TrvDecisionPoint,
} from './trvDecisionPoints';

const refreshIntervalSeconds = 60;

export interface TrvDesiredTargetTemperature {
  readonly climateEntityId: ClimateEntityId;
  readonly targetTemperature: Temperature;
}

function getTrvDesiredTargetTemperature({
  roomTargetTemperature,
  roomTemperature,
  climateEntityId,
  trvTemperature,
}: TrvDecisionPoint): TrvDesiredTargetTemperature {
  const heatingRequired = roomTemperature < roomTargetTemperature;
  const trvTargetTemperature = Math.min(
    MaximumTrvTargetTemperature,
    Math.max(
      MinimumTrvTargetTemperature,
      roomTargetTemperature + trvTemperature - roomTemperature,
    ),
  );

  const roundedTargetTemperature = pipe(
    0.5 *
      (heatingRequired
        ? Math.ceil(trvTargetTemperature * 2.0)
        : Math.floor(trvTargetTemperature * 2.0)),
    Schema.decodeUnknownSync(Temperature),
  );

  return {
    targetTemperature: roundedTargetTemperature,
    climateEntityId,
  };
}

export const getTrvDesiredTargetTemperatures = (
  trvDecisionPoints: Observable<TrvDecisionPoint>,
): Observable<TrvDesiredTargetTemperature> =>
  combineLatest([
    trvDecisionPoints,
    timer(0, refreshIntervalSeconds * 1000),
  ]).pipe(
    map(([decisionPoint]) => getTrvDesiredTargetTemperature(decisionPoint)),
    shareReplayLatestDistinctByKey(
      (trvDesiredTargetTemperature) =>
        trvDesiredTargetTemperature.climateEntityId,
    ),
    share(),
  );
