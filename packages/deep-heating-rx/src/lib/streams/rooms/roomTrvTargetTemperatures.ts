import {
  ClimateTargetTemperature,
  RoomClimateEntities,
  RoomClimateTargetTemperatures,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

export const getRoomTrvTargetTemperatures = (
  roomTrvs$: Observable<RoomClimateEntities>,
  trvTargetTemperatures$: Observable<ClimateTargetTemperature>
): Observable<RoomClimateTargetTemperatures> =>
  roomTrvs$.pipe(
    mergeMap((roomTrvs) => {
      return combineLatest(
        roomTrvs.climateEntityIds.map((trvId) =>
          trvTargetTemperatures$.pipe(
            filter(
              (trvTargetTemperature) =>
                trvTargetTemperature.climateEntityId === trvId
            )
          )
        )
      ).pipe(
        map((trvTargetTemperatures) => ({
          roomName: roomTrvs.roomName,
          climateTargetTemperatures: trvTargetTemperatures,
        })),
        shareReplayLatestDistinctByKey((x) => x.roomName)
      );
    })
  );
