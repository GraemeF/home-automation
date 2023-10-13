import { RoomDefinition, RoomTrvs } from '@home-automation/deep-heating-types';
import { Predicate } from 'effect';
import { GroupedObservable, Observable } from 'rxjs';
import { map, mergeMap } from 'rxjs/operators';

export function getRoomTrvs(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>
): Observable<RoomTrvs> {
  return rooms$.pipe(
    mergeMap((room$) =>
      room$.pipe(
        map((roomDefinition) =>
          roomDefinition.climateEntityIds.filter(Predicate.isNotNull)
        ),
        map((trvControlIds) => ({
          roomName: room$.key,
          climateEntityIds: trvControlIds,
        }))
      )
    )
  );
}
