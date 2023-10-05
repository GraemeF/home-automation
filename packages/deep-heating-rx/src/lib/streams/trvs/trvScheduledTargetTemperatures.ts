import { map, shareReplay } from 'rxjs/operators';
import { combineLatest, Observable, timer } from 'rxjs';
import { DateTime } from 'luxon';
import {
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { toHeatingSchedule } from '@home-automation/deep-heating-hive';
const refreshIntervalSeconds = 60;

export function getTrvScheduledTargetTemperatures(
  trvHiveHeatingSchedule$: Observable<TrvWeekHeatingSchedule>
): Observable<TrvScheduledTargetTemperature> {
  const time = timer(0, refreshIntervalSeconds * 1000).pipe(
    map(() => DateTime.local()),
    shareReplay(1)
  );

  return combineLatest([trvHiveHeatingSchedule$, time]).pipe(
    map(([trvSchedule, now]) => ({
      trvId: trvSchedule.trvId,
      scheduledTargetTemperature: toHeatingSchedule(
        trvSchedule.schedule,
        now
      )[0].targetTemperature,
    }))
  );
}
