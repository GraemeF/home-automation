import {
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { Observable, combineLatest, timer } from 'rxjs';
import { map, shareReplay } from 'rxjs/operators';
const refreshIntervalSeconds = 60;

export const getTrvScheduledTargetTemperatures = (
  trvHiveHeatingSchedule$: Observable<TrvWeekHeatingSchedule>
): Observable<TrvScheduledTargetTemperature> =>
  combineLatest([
    trvHiveHeatingSchedule$,
    timer(0, refreshIntervalSeconds * 1000).pipe(
      map(() => DateTime.local()),
      shareReplay(1)
    ),
  ]).pipe(
    map(([trvSchedule, now]) => ({
      climateEntityId: trvSchedule.climateEntityId,
      scheduledTargetTemperature: toHeatingSchedule(
        trvSchedule.schedule,
        now
      )[0].targetTemperature,
    }))
  );
