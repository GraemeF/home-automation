import { map } from 'rxjs/operators';
import { Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { TrvControlState } from '@home-automation/deep-heating-hive';
import { TrvMode } from '@home-automation/deep-heating-types';

export function getTrvModes(
  trvControlStates: Observable<TrvControlState>
): Observable<TrvMode> {
  return trvControlStates.pipe(
    map((x) => ({ trvId: x.trvId, mode: x.mode, source: x.source })),
    shareReplayLatestDistinctByKey(
      (x) => x.trvId,
      (a, b) => a.mode === b.mode
    )
  );
}
