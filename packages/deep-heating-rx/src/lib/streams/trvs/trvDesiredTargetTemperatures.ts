import { TrvDecisionPoint } from './trvDecisionPoints';
import { combineLatest, Observable, timer } from 'rxjs';
import { map, share } from 'rxjs/operators';
import { DateTime } from 'luxon';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';

const refreshIntervalSeconds = 60;

export interface TrvDesiredTargetTemperature {
  trvId: string;
  targetTemperature: number;
}

function getTrvDesiredTargetTemperature({
  roomTargetTemperature,
  roomTemperature,
  trvId,
  trvTemperature,
}: TrvDecisionPoint): TrvDesiredTargetTemperature {
  const heatingRequired = roomTemperature < roomTargetTemperature;
  const trvTargetTemperature =
    roomTargetTemperature + trvTemperature - roomTemperature;

  const roundedTargetTemperature =
    0.5 *
    (heatingRequired
      ? Math.ceil(trvTargetTemperature * 2.0)
      : Math.floor(trvTargetTemperature * 2.0));

  return {
    targetTemperature: roundedTargetTemperature,
    trvId: trvId,
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
      (trvDesiredTargetTemperature) => trvDesiredTargetTemperature.trvId
    ),
    share()
  );
}
