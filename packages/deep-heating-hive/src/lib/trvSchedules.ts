import { map } from 'rxjs/operators';
import { Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { WeekHeatingSchedule } from '@home-automation/deep-heating-types';
import { TrvUpdate } from './hive';

export interface TrvHiveHeatingSchedule {
  trvId: string;
  schedule: WeekHeatingSchedule;
}

export function getTrvHiveHeatingSchedules(
  trvUpdates$: Observable<TrvUpdate>
): Observable<TrvHiveHeatingSchedule> {
  return trvUpdates$.pipe(
    map((x) => ({
      trvId: x.trvId,
      schedule: x.state.schedule,
    })),
    shareReplayLatestDistinctByKey((x) => x.trvId)
  );
}
