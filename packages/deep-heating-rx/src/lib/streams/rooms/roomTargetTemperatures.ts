import { Schema } from '@effect/schema';
import {
  RoomAdjustment,
  RoomDefinition,
  RoomMode,
  RoomTargetTemperature,
  Temperature,
} from '@home-automation/deep-heating-types';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
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

  switch (roomMode.mode) {
    case 'Sleeping':
      return MinimumRoomTargetTemperature;
    case 'Off':
      return MinimumTrvTargetTemperature;
    default:
      return Schema.decodeUnknownSync(Temperature)(
        Math.max(
          MinimumRoomTargetTemperature,
          roomScheduledTargetTemperature.targetTemperature +
            roomAdjustment.adjustment,
        ),
      );
  }
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
