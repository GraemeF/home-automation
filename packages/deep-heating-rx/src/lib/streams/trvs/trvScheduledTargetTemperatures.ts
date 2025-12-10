import {
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
import { Observable, combineLatest, timer } from 'rxjs';
import { groupBy, map, mergeMap, shareReplay } from 'rxjs/operators';
import { localNow } from '../../utils/datetime';
const refreshIntervalSeconds = 60;

export const getTrvScheduledTargetTemperatures = (
  trvHiveHeatingSchedule$: Observable<TrvWeekHeatingSchedule>,
): Observable<TrvScheduledTargetTemperature> =>
  trvHiveHeatingSchedule$.pipe(
    groupBy((schedule) => schedule.climateEntityId),
    mergeMap((trvScheduleGroup$) =>
      combineLatest([
        timer(0, refreshIntervalSeconds * 1000).pipe(
          map(localNow),
          shareReplay(1),
        ),
        trvScheduleGroup$,
      ]).pipe(shareReplayLatestDistinct()),
    ),
    map(([now, trvSchedule]) => ({
      climateEntityId: trvSchedule.climateEntityId,
      scheduledTargetTemperature: toHeatingSchedule(
        trvSchedule.schedule,
        now,
      )[0].targetTemperature,
    })),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
  );
