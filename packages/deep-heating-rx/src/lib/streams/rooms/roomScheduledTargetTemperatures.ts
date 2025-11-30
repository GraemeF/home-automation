import { pipe, Schema } from 'effect';
import {
  HeatingSchedule,
  RoomDefinition,
  RoomSchedule,
  RoomTargetTemperature,
  Temperature,
} from '@home-automation/deep-heating-types';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
import { DateTime } from 'luxon';
import { GroupedObservable, Observable, combineLatest, timer } from 'rxjs';
import { filter, map, mergeMap, shareReplay } from 'rxjs/operators';

const refreshIntervalSeconds = 60;

const getScheduledTargetTemperature = (
  schedule: HeatingSchedule,
  time: DateTime,
) => {
  const maxTemperature = Math.max(
    ...schedule.map(
      (entry) =>
        Math.round(
          (entry.targetTemperature -
            0.5 *
              Math.max(
                0.0,
                DateTime.fromJSDate(entry.start).diff(time).as('hours'),
              )) *
            10,
        ) / 10,
    ),
  );
  return pipe(maxTemperature, Schema.decodeUnknownSync(Temperature));
};

export const getRoomScheduledTargetTemperatures = (
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomSchedules$: Observable<RoomSchedule>,
): Observable<RoomTargetTemperature> =>
  rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        timer(0, refreshIntervalSeconds * 1000).pipe(
          // eslint-disable-next-line effect/no-eta-expansion
          map(() => DateTime.local()),
          shareReplay(1),
        ),
        room,
        roomSchedules$.pipe(filter((x) => x.roomName === room.key)),
      ]).pipe(shareReplayLatestDistinct()),
    ),
    map(([time, room, roomSchedule]) => ({
      roomName: room.name,
      targetTemperature: getScheduledTargetTemperature(
        roomSchedule.schedule,
        time,
      ),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName),
  );
