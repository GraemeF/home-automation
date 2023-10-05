import { filter, map, mergeMap } from 'rxjs/operators';
import { combineLatest, Observable } from 'rxjs';
import { RoomTrvModes, TrvMode } from '@home-automation/deep-heating-types';
import { RoomTrvs } from '@home-automation/deep-heating-hive';

export function getRoomTrvModes(
  roomTrvs$: Observable<RoomTrvs>,
  trvModes$: Observable<TrvMode>
): Observable<RoomTrvModes> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.trvIds.map((trvId) =>
          trvModes$.pipe(filter((trvMode) => trvMode.trvId === trvId))
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
