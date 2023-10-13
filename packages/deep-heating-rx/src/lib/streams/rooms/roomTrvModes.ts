import {
  RoomTrvModes,
  RoomTrvs,
  TrvMode,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export function getRoomTrvModes(
  roomTrvs$: Observable<RoomTrvs>,
  trvModes$: Observable<TrvMode>
): Observable<RoomTrvModes> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.climateEntityIds.map((trvId) =>
          trvModes$.pipe(filter((trvMode) => trvMode.climateEntityId === trvId))
        )
      ).pipe(
        map((trvModes) => ({
          roomName: roomTrvs.roomName,
          trvModes: trvModes,
        }))
      )
    )
  );
}
