import {
  ClimateEntityId,
  RoomDecisionPoint,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { mergeMap, share } from 'rxjs/operators';

export function getTrvDecisionPoints(
  roomDecisionPoints$: Observable<RoomDecisionPoint>
): Observable<TrvDecisionPoint> {
  return roomDecisionPoints$.pipe(
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
            )?.mode ?? 'OFF',
        }))
    ),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    share()
  );
}

export interface TrvDecisionPoint {
  climateEntityId: ClimateEntityId;
  trvTemperature: Temperature;
  roomTemperature: Temperature;
  roomTargetTemperature: Temperature;
  trvMode: string;
}
