import {
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest, timer } from 'rxjs';
import { map, shareReplay } from 'rxjs/operators';
import { localNow } from '../../utils/datetime';
const refreshIntervalSeconds = 60;

export const getTrvScheduledTargetTemperatures = (
  trvHiveHeatingSchedule$: Observable<TrvWeekHeatingSchedule>,
): Observable<TrvScheduledTargetTemperature> =>
  combineLatest([
    trvHiveHeatingSchedule$,
    timer(0, refreshIntervalSeconds * 1000).pipe(map(localNow), shareReplay(1)),
  ]).pipe(
    map(([trvSchedule, now]) => ({
      climateEntityId: trvSchedule.climateEntityId,
      scheduledTargetTemperature: toHeatingSchedule(
        trvSchedule.schedule,
        now,
      )[0].targetTemperature,
    })),
  );
