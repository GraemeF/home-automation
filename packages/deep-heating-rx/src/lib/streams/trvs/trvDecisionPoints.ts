import { Observable } from 'rxjs';
import { mergeMap, share } from 'rxjs/operators';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { RoomDecisionPoint } from '@home-automation/deep-heating-types';

export function getTrvDecisionPoints(
  roomDecisionPoints$: Observable<RoomDecisionPoint>
): Observable<TrvDecisionPoint> {
  return roomDecisionPoints$.pipe(
    mergeMap((roomDecisionPoint) =>
      roomDecisionPoint.trvTargetTemperatures
        .map((y) => y.trvId)
        .map((trvId) => ({
          roomTargetTemperature: roomDecisionPoint.targetTemperature,
          roomTemperature: roomDecisionPoint.temperature,
          trvTemperature:
            roomDecisionPoint.trvTemperatures.find(
              (trvTemperature) => trvTemperature.trvId === trvId
            )?.temperatureReading.temperature ?? roomDecisionPoint.temperature,
          trvId: trvId,
          trvMode:
            roomDecisionPoint.trvModes.find(
              (trvMode) => trvMode.trvId === trvId
            )?.mode ?? 'OFF',
        }))
    ),
    shareReplayLatestDistinctByKey((x) => x.trvId),
    share()
  );
}

export interface TrvDecisionPoint {
  trvId: string;
  trvTemperature: number;
  roomTemperature: number;
  roomTargetTemperature: number;
  trvMode: string;
}
