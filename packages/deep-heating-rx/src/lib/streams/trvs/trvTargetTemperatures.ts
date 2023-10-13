import {
  ClimateTargetTemperature,
  TrvControlState,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export function getTrvTargetTemperatures(
  trvControlStates$: Observable<TrvControlState>
): Observable<ClimateTargetTemperature> {
  return trvControlStates$.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      targetTemperature: x.targetTemperature,
    })),
    shareReplayLatestDistinctByKey(
      (x) => x.climateEntityId,
      (a, b) => a.targetTemperature === b.targetTemperature
    )
  );
}
