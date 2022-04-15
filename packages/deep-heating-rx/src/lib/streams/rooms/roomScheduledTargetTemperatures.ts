import { combineLatest, GroupedObservable, Observable, timer } from 'rxjs';
import { filter, map, mergeMap, shareReplay } from 'rxjs/operators';
import { DateTime } from 'luxon';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
import {
  HeatingSchedule,
  RoomDefinition,
  RoomSchedule,
  RoomTargetTemperature,
} from '@home-automation/deep-heating-types';

const refreshIntervalSeconds = 60;

function getScheduledTargetTemperature(
  schedule: HeatingSchedule,
  time: DateTime
) {
  return Math.max(
    ...schedule.map(
      (entry) =>
        Math.round(
          (entry.targetTemperature -
            0.5 * Math.max(0.0, entry.start.diff(time).as('hours'))) *
            10
        ) / 10
    )
  );
}

export function getRoomScheduledTargetTemperatures(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomSchedules$: Observable<RoomSchedule>
): Observable<RoomTargetTemperature> {
  const time = timer(0, refreshIntervalSeconds * 1000).pipe(
    map(() => DateTime.local()),
    shareReplay(1)
  );
  return rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        time,
        room,
        roomSchedules$.pipe(filter((x) => x.roomName === room.key)),
      ]).pipe(shareReplayLatestDistinct())
    ),
    map(([time, room, roomSchedule]) => ({
      roomName: room.name,
      targetTemperature: getScheduledTargetTemperature(
        roomSchedule.schedule,
        time
      ),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName)
  );
}
