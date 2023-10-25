import {
  RoomDefinition,
  RoomSchedule,
  RoomWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { ReadonlyArray, pipe } from 'effect';
import { DateTime } from 'luxon';
import { Observable, combineLatest, timer } from 'rxjs';
import { filter, map, mergeMap, shareReplay } from 'rxjs/operators';

const refreshIntervalSeconds = 60;

export function getRoomSchedules(
  rooms$: Observable<RoomDefinition>,
  roomHiveHeatingSchedules: Observable<RoomWeekHeatingSchedule>
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
        map(([time, roomSchedule]) => ({
          roomName: roomSchedule.roomName,
          schedule: pipe(
            toHeatingSchedule(roomSchedule.schedule, time),
            ReadonlyArray.take(3)
          ),
        }))
      )
    )
  );
}