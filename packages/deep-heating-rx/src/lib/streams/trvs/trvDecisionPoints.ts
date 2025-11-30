import { pipe, Schema } from 'effect';
import {
  ClimateEntityId,
  ClimateMode,
  RoomDecisionPoint,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { mergeMap, share } from 'rxjs/operators';

export const getTrvDecisionPoints = (
  roomDecisionPoints$: Observable<RoomDecisionPoint>,
): Observable<TrvDecisionPoint> =>
  roomDecisionPoints$.pipe(
    mergeMap((roomDecisionPoint) =>
      roomDecisionPoint.trvTargetTemperatures
        .map((y) => y.climateEntityId)
        .map((trvId) => ({
          roomTargetTemperature: roomDecisionPoint.targetTemperature,
          roomTemperature: roomDecisionPoint.temperature,
          trvTemperature:
            roomDecisionPoint.trvTemperatures.find(
              (trvTemperature) => trvTemperature.climateEntityId === trvId,
            )?.temperatureReading.temperature ?? roomDecisionPoint.temperature,
          climateEntityId: trvId,
          trvMode:
            roomDecisionPoint.trvModes.find(
              (trvMode) => trvMode.climateEntityId === trvId,
            )?.mode ?? 'off',
        })),
    ),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    share(),
  );

export const MinimumRoomTargetTemperature = pipe(
  15,
  Schema.decodeUnknownSync(Temperature),
);
export const MinimumTrvTargetTemperature = pipe(
  7,
  Schema.decodeUnknownSync(Temperature),
);
export const MaximumTrvTargetTemperature = pipe(
  32,
  Schema.decodeUnknownSync(Temperature),
);

export const TrvDecisionPoint = Schema.Struct({
  climateEntityId: ClimateEntityId,
  trvTemperature: Temperature,
  roomTemperature: Temperature,
  roomTargetTemperature: Temperature,
  trvMode: ClimateMode,
});
export type TrvDecisionPoint = typeof TrvDecisionPoint.Type;
