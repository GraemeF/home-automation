import {
  RoomClimateTargetTemperatures,
  RoomDecisionPoint,
  RoomDefinition,
  RoomTargetTemperature,
  RoomTemperature,
  RoomTrvModes,
  RoomTrvTemperatures,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';
import debug from 'debug';
import { GroupedObservable, Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap, share, tap } from 'rxjs/operators';

const log = debug('deep-heating:room-decision-points');

export const getRoomDecisionPoints = (
  rooms: Observable<GroupedObservable<string, RoomDefinition>>,
  roomTargetTemperatures: Observable<RoomTargetTemperature>,
  roomTemperatures: Observable<RoomTemperature>,
  roomTrvTargetTemperatures: Observable<RoomClimateTargetTemperatures>,
  roomTrvTemperatures: Observable<RoomTrvTemperatures>,
  roomTrvModes: Observable<RoomTrvModes>,
): Observable<RoomDecisionPoint> =>
  rooms.pipe(
    mergeMap((room) => {
      log('[%s] 🔌 Subscribing to room streams...', room.key);
      return combineLatest([
        room,
        roomTargetTemperatures.pipe(
          filter((x) => x.roomName === room.key),
          tap(() => {
            log('[%s] ✓ roomTargetTemperature received', room.key);
          }),
        ),
        roomTemperatures.pipe(
          filter((x) => x.roomName === room.key),
          tap(() => {
            log('[%s] ✓ roomTemperature received', room.key);
          }),
        ),
        roomTrvTargetTemperatures.pipe(
          filter((x) => x.roomName === room.key),
          tap(() => {
            log('[%s] ✓ roomTrvTargetTemperatures received', room.key);
          }),
        ),
        roomTrvTemperatures.pipe(
          filter((x) => x.roomName === room.key),
          tap(() => {
            log('[%s] ✓ roomTrvTemperatures received', room.key);
          }),
        ),
        roomTrvModes.pipe(
          filter((x) => x.roomName === room.key),
          tap(() => {
            log('[%s] ✓ roomTrvModes received', room.key);
          }),
        ),
      ]).pipe(shareReplayLatestDistinct());
    }),
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
        trvTargetTemperatures:
          roomTrvTargetTemperatures.climateTargetTemperatures,
        trvTemperatures: roomTrvTemperatures.trvTemperatures,
        trvModes: roomTrvModes.trvModes,
      }),
    ),
    share(),
  );
