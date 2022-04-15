import { combineLatest, Observable, timer } from 'rxjs';
import { DateTime } from 'luxon';
import { filter, map, mergeMap, shareReplay } from 'rxjs/operators';
import { toHeatingSchedule } from '../hiveSchedule';
import {
  RoomDefinition,
  RoomSchedule,
} from '@home-automation/deep-heating-types';
import { RoomHiveHeatingSchedule } from '@home-automation/deep-heating-hive';

const refreshIntervalSeconds = 60;

export function getRoomSchedules(
  rooms$: Observable<RoomDefinition>,
  roomHiveHeatingSchedules: Observable<RoomHiveHeatingSchedule>
): Observable<RoomSchedule> {
  const time = timer(0, refreshIntervalSeconds * 1000).pipe(
    map(() => DateTime.local()),
    shareReplay(1)
  );

  return rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        time,
        roomHiveHeatingSchedules.pipe(filter((x) => x.roomName === room.name)),
      ]).pipe(
        map(([time, roomSchedule]) => {
          return {
            roomName: roomSchedule.roomName,
            schedule: toHeatingSchedule(roomSchedule.schedule, time).splice(
              0,
              3
            ),
          };
        })
      )
    )
  );
}
