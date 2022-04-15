import { combineLatest, GroupedObservable, Observable } from 'rxjs';
import { filter, map, mergeMap, share } from 'rxjs/operators';
import { RoomTrvTargetTemperatures } from './roomTrvs';
import {
  RoomDecisionPoint,
  RoomDefinition,
  RoomTargetTemperature,
  RoomTemperature,
  RoomTrvModes,
  RoomTrvTemperatures,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';

export function getRoomDecisionPoints(
  rooms: Observable<GroupedObservable<string, RoomDefinition>>,
  roomTargetTemperatures: Observable<RoomTargetTemperature>,
  roomTemperatures: Observable<RoomTemperature>,
  roomTrvTargetTemperatures: Observable<RoomTrvTargetTemperatures>,
  roomTrvTemperatures: Observable<RoomTrvTemperatures>,
  roomTrvModes: Observable<RoomTrvModes>
): Observable<RoomDecisionPoint> {
  return rooms.pipe(
    mergeMap((room) =>
      combineLatest([
        room,
        roomTargetTemperatures.pipe(filter((x) => x.roomName === room.key)),
        roomTemperatures.pipe(filter((x) => x.roomName === room.key)),
        roomTrvTargetTemperatures.pipe(filter((x) => x.roomName === room.key)),
        roomTrvTemperatures.pipe(filter((x) => x.roomName === room.key)),
        roomTrvModes.pipe(filter((x) => x.roomName === room.key)),
      ]).pipe(shareReplayLatestDistinct())
    ),
    map(
      ([
        room,
        roomTargetTemperature,
        roomTemperature,
        roomTrvTargetTemperatures,
        roomTrvTemperatures,
        roomTrvModes,
      ]) => ({
        roomName: room.name,
        targetTemperature: roomTargetTemperature.targetTemperature,
        temperature: roomTemperature.temperatureReading.temperature,
        trvTargetTemperatures: roomTrvTargetTemperatures.trvTargetTemperatures,
        trvTemperatures: roomTrvTemperatures.trvTargetTemperatures,
        trvModes: roomTrvModes.trvModes,
      })
    ),
    share()
  );
}
