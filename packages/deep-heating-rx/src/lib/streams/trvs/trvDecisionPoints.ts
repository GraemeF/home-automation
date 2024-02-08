import { Schema } from '@effect/schema';
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

export const MinimumRoomTargetTemperature =
  Schema.decodeUnknownSync(Temperature)(15);
export const MinimumTrvTargetTemperature =
  Schema.decodeUnknownSync(Temperature)(7);
export const MaximumTrvTargetTemperature =
  Schema.decodeUnknownSync(Temperature)(32);

export const TrvDecisionPoint = Schema.struct({
  climateEntityId: ClimateEntityId,
  trvTemperature: Temperature,
  roomTemperature: Temperature,
  roomTargetTemperature: Temperature,
  trvMode: ClimateMode,
});
export type TrvDecisionPoint = Schema.Schema.To<typeof TrvDecisionPoint>;
