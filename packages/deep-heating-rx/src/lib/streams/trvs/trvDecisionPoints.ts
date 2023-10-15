import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  HassState,
  RoomDecisionPoint,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { mergeMap, share } from 'rxjs/operators';

export const getTrvDecisionPoints = (
  roomDecisionPoints$: Observable<RoomDecisionPoint>
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
              (trvTemperature) => trvTemperature.climateEntityId === trvId
            )?.temperatureReading.temperature ?? roomDecisionPoint.temperature,
          climateEntityId: trvId,
          trvMode:
            roomDecisionPoint.trvModes.find(
              (trvMode) => trvMode.climateEntityId === trvId
            )?.mode ?? 'off',
        }))
    ),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    share()
  );

export const TrvDecisionPoint = Schema.struct({
  climateEntityId: ClimateEntityId,
  trvTemperature: Temperature,
  roomTemperature: Temperature,
  roomTargetTemperature: Temperature,
  trvMode: HassState,
});
export type TrvDecisionPoint = Schema.Schema.To<typeof TrvDecisionPoint>;
