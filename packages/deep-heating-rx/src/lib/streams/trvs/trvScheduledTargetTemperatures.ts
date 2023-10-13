import {
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { Observable, combineLatest, timer } from 'rxjs';
import { map, shareReplay } from 'rxjs/operators';
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
      climateEntityId: trvSchedule.climateEntityId,
      scheduledTargetTemperature: toHeatingSchedule(
        trvSchedule.schedule,
        now
      )[0].targetTemperature,
    }))
  );
}
