import {
  ClimateEntityStatus,
  RoomClimateEntities,
  RoomTrvStatuses,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export function getRoomTrvStatuses(
  roomTrvs$: Observable<RoomClimateEntities>,
  climateEntityStatus$: Observable<ClimateEntityStatus>
): Observable<RoomTrvStatuses> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) =>
      combineLatest(
        roomTrvs.climateEntityIds.map((trvId) =>
          climateEntityStatus$.pipe(
            filter(
              (climateEntityStatus) =>
                climateEntityStatus.climateEntityId === trvId
            )
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
