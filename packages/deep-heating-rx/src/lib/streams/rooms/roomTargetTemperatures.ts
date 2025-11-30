import {
  decodeTemperature,
  RoomAdjustment,
  RoomDefinition,
  RoomMode,
  RoomTargetTemperature,
} from '@home-automation/deep-heating-types';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
import { Match } from 'effect';
import { GroupedObservable, Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';
import {
  MinimumRoomTargetTemperature,
  MinimumTrvTargetTemperature,
} from '../trvs/trvDecisionPoints';

const getTargetTemperature = (
  roomScheduledTargetTemperature: RoomTargetTemperature,
  roomMode: RoomMode,
  roomAdjustment: RoomAdjustment,
) => {
  if (roomAdjustment.roomName !== roomScheduledTargetTemperature.roomName)
    throw Error('Mismatched rooms');

  return Match.value(roomMode.mode).pipe(
    Match.when('Sleeping', () => MinimumRoomTargetTemperature),
    Match.when('Off', () => MinimumTrvTargetTemperature),
    Match.when('Auto', () =>
      decodeTemperature(
        Math.max(
          MinimumRoomTargetTemperature,
          roomScheduledTargetTemperature.targetTemperature +
            roomAdjustment.adjustment,
        ),
      ),
    ),
    Match.exhaustive,
  );
};

export const getRoomTargetTemperatures = (
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomModes$: Observable<RoomMode>,
  roomScheduledTargetTemperatures$: Observable<RoomTargetTemperature>,
  roomAdjustments$: Observable<RoomAdjustment>,
): Observable<RoomTargetTemperature> =>
  rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        room,
        roomModes$.pipe(filter((x) => x.roomName === room.key)),
        roomScheduledTargetTemperatures$.pipe(
          filter((x) => x.roomName === room.key),
        ),
        roomAdjustments$.pipe(filter((x) => x.roomName === room.key)),
      ]).pipe(shareReplayLatestDistinct()),
    ),
    map(([room, roomMode, roomScheduledTargetTemperature, roomAdjustment]) => ({
      roomName: room.name,
      targetTemperature: getTargetTemperature(
        roomScheduledTargetTemperature,
        roomMode,
        roomAdjustment,
      ),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName),
  );
