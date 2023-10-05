import { filter, map, mergeMap } from 'rxjs/operators';
import { combineLatest, Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { TrvTargetTemperature } from '@home-automation/deep-heating-types';
import {
  RoomTrvTargetTemperatures,
  RoomTrvs,
} from '@home-automation/deep-heating-hive';

export function getRoomTrvTargetTemperatures(
  roomTrvs$: Observable<RoomTrvs>,
  trvTargetTemperatures$: Observable<TrvTargetTemperature>
): Observable<RoomTrvTargetTemperatures> {
  return roomTrvs$.pipe(
    mergeMap((roomTrvs) => {
      return combineLatest(
        roomTrvs.trvIds.map((trvId) =>
          trvTargetTemperatures$.pipe(
            filter(
              (trvTargetTemperature) => trvTargetTemperature.trvId === trvId
            )
          )
        )
      ).pipe(
        map((trvTargetTemperatures) => ({
          roomName: roomTrvs.roomName,
          trvTargetTemperatures: trvTargetTemperatures,
        })),
        shareReplayLatestDistinctByKey((x) => x.roomName)
      );
    })
  );
}
