import { filter, map, mergeMap } from 'rxjs/operators';
import { RoomTrvs } from './roomTrvs';
import { combineLatest, Observable } from 'rxjs';
import {
  RoomTrvTemperatures,
  TrvTemperature,
} from '@home-automation/deep-heating-types';

export function getRoomTrvTemperatures(
  roomTrvs$: Observable<RoomTrvs>,
  trvTemperatures: Observable<TrvTemperature>
): Observable<RoomTrvTemperatures> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.trvIds.map((trvId) =>
          trvTemperatures.pipe(
            filter((trvTemperature) => trvTemperature.trvId === trvId)
          )
        )
      ).pipe(
        map((trvTemperatures) => ({
          roomName: roomTrvs.roomName,
          trvTargetTemperatures: trvTemperatures,
        }))
      )
    )
  );
}
