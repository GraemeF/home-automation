import { combineLatest, GroupedObservable, Observable } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';
import {
  shareReplayLatestDistinct,
  shareReplayLatestDistinctByKey,
} from '@home-automation/rxx';
import {
  RoomAdjustment,
  RoomDefinition,
  RoomMode,
  RoomTargetTemperature,
} from '@home-automation/deep-heating-types';

function getTargetTemperature(
  roomScheduledTargetTemperature: RoomTargetTemperature,
  roomMode: RoomMode,
  roomAdjustment: RoomAdjustment
) {
  if (roomAdjustment.roomName !== roomScheduledTargetTemperature.roomName)
    throw Error('Mismatched rooms');

  switch (roomMode.mode) {
    case 'Sleeping':
    case 'Off':
      return 7;
    default:
      return (
        roomScheduledTargetTemperature.targetTemperature +
        roomAdjustment.adjustment
      );
  }
}

export function getRoomTargetTemperatures(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomModes$: Observable<RoomMode>,
  roomScheduledTargetTemperatures$: Observable<RoomTargetTemperature>,
  roomAdjustments$: Observable<RoomAdjustment>
): Observable<RoomTargetTemperature> {
  return rooms$.pipe(
    mergeMap((room) =>
      combineLatest([
        room,
        roomModes$.pipe(filter((x) => x.roomName === room.key)),
        roomScheduledTargetTemperatures$.pipe(
          filter((x) => x.roomName === room.key)
        ),
        roomAdjustments$.pipe(filter((x) => x.roomName === room.key)),
      ]).pipe(shareReplayLatestDistinct())
    ),
    map(([room, roomMode, roomScheduledTargetTemperature, roomAdjustment]) => ({
      roomName: room.name,
      targetTemperature: getTargetTemperature(
        roomScheduledTargetTemperature,
        roomMode,
        roomAdjustment
      ),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName)
  );
}
