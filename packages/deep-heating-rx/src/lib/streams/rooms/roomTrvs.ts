import { map, mergeMap } from 'rxjs/operators';
import { GroupedObservable, Observable } from 'rxjs';
import { RoomDefinition, RoomTrvs } from '@home-automation/deep-heating-types';
import { isNotNull } from '../filters';

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
