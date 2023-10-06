import { map, mergeMap } from 'rxjs/operators';
import { GroupedObservable, Observable } from 'rxjs';
import { RoomDefinition, RoomTrvs } from '@home-automation/deep-heating-types';
import { Predicate } from 'effect';

export function getRoomTrvs(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>
): Observable<RoomTrvs> {
  return rooms$.pipe(
    mergeMap((room$) =>
      room$.pipe(
        map((roomDefinition) =>
          roomDefinition.trvControlIds.filter(Predicate.isNotNull)
        ),
        map((trvControlIds) => ({
          roomName: room$.key,
          trvIds: trvControlIds,
        }))
      )
    )
  );
}
