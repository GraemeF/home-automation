import { TrvControlState, TrvMode } from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export function getTrvModes(
  trvControlStates: Observable<TrvControlState>
): Observable<TrvMode> {
  return trvControlStates.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      mode: x.mode,
      source: x.source,
    })),
    shareReplayLatestDistinctByKey(
      (x) => x.climateEntityId,
      (a, b) => a.mode === b.mode
    )
  );
}
