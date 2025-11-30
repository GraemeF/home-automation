import {
  RoomDefinition,
  RoomSchedule,
  RoomWeekHeatingSchedule,
  toHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { Array, pipe } from 'effect';
import { DateTime } from 'luxon';
import { Observable, combineLatest, timer } from 'rxjs';
import { filter, map, mergeMap, shareReplay } from 'rxjs/operators';

const refreshIntervalSeconds = 60;

export const getRoomSchedules = (
  rooms$: Observable<RoomDefinition>,
  roomHiveHeatingSchedules: Observable<RoomWeekHeatingSchedule>,
): Observable<RoomSchedule> =>
  rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        timer(0, refreshIntervalSeconds * 1000).pipe(
          // eslint-disable-next-line effect/no-eta-expansion
          map(() => DateTime.local()),
          shareReplay(1),
        ),
        roomHiveHeatingSchedules.pipe(filter((x) => x.roomName === room.name)),
      ]).pipe(
        map(([time, roomSchedule]) => ({
          roomName: roomSchedule.roomName,
          schedule: pipe(
            toHeatingSchedule(roomSchedule.schedule, time),
            Array.take(3),
          ),
        })),
      ),
    ),
  );
