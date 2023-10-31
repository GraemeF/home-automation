import {
  RoomClimateEntities,
  RoomTrvModes,
  TrvMode,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export const getRoomTrvModes = (
  roomTrvs$: Observable<RoomClimateEntities>,
  trvModes$: Observable<TrvMode>
): Observable<RoomTrvModes> =>
  roomTrvs$.pipe(
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
