import { map } from 'rxjs/operators';
import { Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { TrvControlState } from '@home-automation/deep-heating-hive';
import { TrvTargetTemperature } from '@home-automation/deep-heating-types';

export function getTrvTargetTemperatures(
  trvControlStates$: Observable<TrvControlState>
): Observable<TrvTargetTemperature> {
  return trvControlStates$.pipe(
    map((x) => ({ trvId: x.trvId, targetTemperature: x.targetTemperature })),
    shareReplayLatestDistinctByKey(
      (x) => x.trvId,
      (a, b) => a.targetTemperature === b.targetTemperature
    )
  );
}
