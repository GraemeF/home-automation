import {
  ClimateTemperatureReading,
  RoomTrvTemperatures,
  RoomTrvs,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export function getRoomTrvTemperatures(
  roomTrvs$: Observable<RoomTrvs>,
  trvTemperatures: Observable<ClimateTemperatureReading>
): Observable<RoomTrvTemperatures> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.climateEntityIds.map((trvId) =>
          trvTemperatures.pipe(
            filter((trvTemperature) => trvTemperature.climateEntityId === trvId)
          )
        )
      ).pipe(
        map((trvTemperatures) => ({
          roomName: roomTrvs.roomName,
          trvTemperatures: trvTemperatures,
        }))
      )
    )
  );
}
