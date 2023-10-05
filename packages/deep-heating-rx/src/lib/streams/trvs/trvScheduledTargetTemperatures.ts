import { map, shareReplay } from 'rxjs/operators';
import { combineLatest, Observable, timer } from 'rxjs';
import { DateTime } from 'luxon';
import { TrvScheduledTargetTemperature } from '@home-automation/deep-heating-types';
import {
  TrvHiveHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-hive';

const refreshIntervalSeconds = 60;

export function getTrvScheduledTargetTemperatures(
  trvHiveHeatingSchedule$: Observable<TrvHiveHeatingSchedule>
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
