import {
  RoomTrvs,
  RoomTrvStatuses,
  TrvStatus,
} from '@home-automation/deep-heating-types';
import { combineLatest, Observable } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export function getRoomTrvStatuses(
  roomTrvs$: Observable<RoomTrvs>,
  trvStatus$: Observable<TrvStatus>
): Observable<RoomTrvStatuses> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.climateEntityIds.map((trvId) =>
          trvStatus$.pipe(
            filter((trvStatus) => trvStatus.climateEntityId === trvId)
          )
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
