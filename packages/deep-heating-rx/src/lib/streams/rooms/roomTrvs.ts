import { map, mergeMap } from 'rxjs/operators';
import { GroupedObservable, Observable } from 'rxjs';
import { isNotNull } from '../filters';
import {
  RoomDefinition,
  TrvTargetTemperature,
} from '@home-automation/deep-heating-types';

export interface RoomTrvs {
  roomName: string;
  trvIds: string[];
}

export interface RoomTrvTargetTemperatures {
  roomName: string;
  trvTargetTemperatures: TrvTargetTemperature[];
}

export function getRoomTrvs(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>
): Observable<RoomTrvs> {
  return rooms$.pipe(
    mergeMap((room$) =>
      room$.pipe(
        map((roomDefinition) => roomDefinition.trvControlIds.filter(isNotNull)),
        map((trvControlIds) => ({
          roomName: room$.key,
          trvIds: trvControlIds,
        }))
      )
    )
  );
}
