import {
  TrvUpdate,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export function getTrvWeekHeatingSchedules(
  trvUpdates$: Observable<TrvUpdate>
): Observable<TrvWeekHeatingSchedule> {
  return trvUpdates$.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      schedule: x.state.schedule,
    })),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId)
  );
}
