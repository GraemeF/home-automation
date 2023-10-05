import { map } from 'rxjs/operators';
import { Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import {
  TrvUpdate,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';

export function getTrvWeekHeatingSchedules(
  trvUpdates$: Observable<TrvUpdate>
): Observable<TrvWeekHeatingSchedule> {
  return trvUpdates$.pipe(
    map((x) => ({
      trvId: x.trvId,
      schedule: x.state.schedule,
    })),
    shareReplayLatestDistinctByKey((x) => x.trvId)
  );
}
