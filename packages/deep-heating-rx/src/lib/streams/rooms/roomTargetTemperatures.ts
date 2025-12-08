import {
  decodeTemperature,
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
import { Data, Either, Match } from 'effect';
import { GroupedObservable, Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';
import {
  MinimumRoomTargetTemperature,
  MinimumTrvTargetTemperature,
} from '../trvs/trvDecisionPoints';

export class MismatchedRoomNames extends Data.TaggedError(
  'MismatchedRoomNames',
)<{
  readonly scheduledRoomName: string;
  readonly adjustmentRoomName: string;
}> {}

export const getTargetTemperature = (
  roomScheduledTargetTemperature: RoomTargetTemperature,
  roomMode: RoomMode,
  roomAdjustment: RoomAdjustment,
): Readonly<Either.Either<Temperature, MismatchedRoomNames>> => {
  if (roomAdjustment.roomName !== roomScheduledTargetTemperature.roomName) {
    return Either.left(
      new MismatchedRoomNames({
        scheduledRoomName: roomScheduledTargetTemperature.roomName,
        adjustmentRoomName: roomAdjustment.roomName,
      }),
    );
  }

  return Either.right(
    Match.value(roomMode.mode).pipe(
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
    ),
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
      temperatureResult: getTargetTemperature(
        roomScheduledTargetTemperature,
        roomMode,
        roomAdjustment,
      ),
    })),
    // Either.left values indicate a bug (mismatched room names) - filter them out
    // The pipeline design should prevent this, but we handle it gracefully
    filter((x) => Either.isRight(x.temperatureResult)),
    map((x) => ({
      roomName: x.roomName,
      targetTemperature: (
        x.temperatureResult as Either.Right<MismatchedRoomNames, Temperature>
      ).right,
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName),
  );
