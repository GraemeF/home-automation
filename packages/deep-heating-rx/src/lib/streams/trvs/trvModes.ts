import { TrvControlState, TrvMode } from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export const getTrvModes = (
  trvControlStates: Observable<TrvControlState>
): Observable<TrvMode> =>
  trvControlStates.pipe(
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
