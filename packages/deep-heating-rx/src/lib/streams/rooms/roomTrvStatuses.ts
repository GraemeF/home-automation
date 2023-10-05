import { combineLatest, Observable } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';
import {
  RoomTrvs,
  RoomTrvStatuses,
  TrvStatus,
} from '@home-automation/deep-heating-types';

export function getRoomTrvStatuses(
  roomTrvs$: Observable<RoomTrvs>,
  trvStatus$: Observable<TrvStatus>
): Observable<RoomTrvStatuses> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.trvIds.map((trvId) =>
          trvStatus$.pipe(filter((trvStatus) => trvStatus.trvId === trvId))
        )
      ).pipe(
        map((trvStatuses) => ({
          roomName: roomTrvs.roomName,
          trvStatuses: trvStatuses,
        }))
      )
    )
  );
}
