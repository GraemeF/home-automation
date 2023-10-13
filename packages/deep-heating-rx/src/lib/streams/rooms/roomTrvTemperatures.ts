import {
  ClimateTemperatureReading,
  RoomClimateEntities,
  RoomTrvTemperatures,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export function getRoomTrvTemperatures(
  roomTrvs$: Observable<RoomClimateEntities>,
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
