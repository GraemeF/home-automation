import {
  ClimateEntityId,
  decodeTemperature,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Observable } from 'rxjs';
import { map, share, tap } from 'rxjs/operators';

import {
  MaximumTrvTargetTemperature,
  MinimumTrvTargetTemperature,
  TrvDecisionPoint,
} from './trvDecisionPoints';

const log = debug('deep-heating:trv-temp-flow');

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

  const roundedTargetTemperature = decodeTemperature(
    0.5 *
      (heatingRequired
        ? Math.ceil(trvTargetTemperature * 2.0)
        : Math.floor(trvTargetTemperature * 2.0)),
  );

  return {
    targetTemperature: roundedTargetTemperature,
    climateEntityId,
  };
}

export const getTrvDesiredTargetTemperatures = (
  trvDecisionPoints: Observable<TrvDecisionPoint>,
): Observable<TrvDesiredTargetTemperature> =>
  trvDecisionPoints.pipe(
    map(getTrvDesiredTargetTemperature),
    shareReplayLatestDistinctByKey(
      (trvDesiredTargetTemperature) =>
        trvDesiredTargetTemperature.climateEntityId,
    ),
    tap((x) => {
      log(
        '[3-trvDesiredTargetTemperatures] %s: target=%d°C',
        x.climateEntityId,
        x.targetTemperature,
      );
    }),
    share(),
  );
