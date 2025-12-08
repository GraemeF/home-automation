import { Schema } from 'effect';
import {
  ClimateEntityId,
  ClimateMode,
  decodeTemperature,
  RoomDecisionPoint,
  Temperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Observable } from 'rxjs';
import { mergeMap, share, tap } from 'rxjs/operators';

const log = debug('deep-heating:trv-temp-flow');

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
    tap((x) => {
      log(
        '[2-trvDecisionPoints] %s: roomTarget=%d, roomTemp=%d, trvTemp=%d',
        x.climateEntityId,
        x.roomTargetTemperature,
        x.roomTemperature,
        x.trvTemperature,
      );
    }),
    share(),
  );

export const MinimumRoomTargetTemperature = decodeTemperature(15);
export const MinimumTrvTargetTemperature = decodeTemperature(7);
export const MaximumTrvTargetTemperature = decodeTemperature(32);

export const TrvDecisionPoint = Schema.Struct({
  climateEntityId: ClimateEntityId,
  trvTemperature: Temperature,
  roomTemperature: Temperature,
  roomTargetTemperature: Temperature,
  trvMode: ClimateMode,
});
export type TrvDecisionPoint = typeof TrvDecisionPoint.Type;
