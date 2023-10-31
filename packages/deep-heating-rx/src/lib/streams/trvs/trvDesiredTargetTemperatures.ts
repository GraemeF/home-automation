import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { DateTime } from 'luxon';
import { Observable, combineLatest, timer } from 'rxjs';
import { map, share } from 'rxjs/operators';
import { TrvDecisionPoint } from './trvDecisionPoints';

const refreshIntervalSeconds = 60;

export interface TrvDesiredTargetTemperature {
  climateEntityId: ClimateEntityId;
  targetTemperature: Temperature;
}

function getTrvDesiredTargetTemperature({
  roomTargetTemperature,
  roomTemperature,
  climateEntityId,
  trvTemperature,
}: TrvDecisionPoint): TrvDesiredTargetTemperature {
  const heatingRequired = roomTemperature < roomTargetTemperature;
  const trvTargetTemperature = Math.min(
    32,
    Math.max(7, roomTargetTemperature + trvTemperature - roomTemperature)
  );

  const roundedTargetTemperature = Schema.parseSync(Temperature)(
    0.5 *
      (heatingRequired
        ? Math.ceil(trvTargetTemperature * 2.0)
        : Math.floor(trvTargetTemperature * 2.0))
  );

  return {
    targetTemperature: roundedTargetTemperature,
    climateEntityId,
  };
}

export function getTrvDesiredTargetTemperatures(
  trvDecisionPoints: Observable<TrvDecisionPoint>
): Observable<TrvDesiredTargetTemperature> {
  const time = timer(0, refreshIntervalSeconds * 1000).pipe(
    map(() => DateTime.local())
  );

  return combineLatest([trvDecisionPoints, time]).pipe(
    map(([decisionPoint]) => getTrvDesiredTargetTemperature(decisionPoint)),
    shareReplayLatestDistinctByKey(
      (trvDesiredTargetTemperature) =>
        trvDesiredTargetTemperature.climateEntityId
    ),
    share()
  );
}
