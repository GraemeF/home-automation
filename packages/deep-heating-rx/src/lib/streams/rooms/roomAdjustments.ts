import { GroupedObservable, Observable } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  mergeMap,
  shareReplay,
  startWith,
} from 'rxjs/operators';
import { isDeepStrictEqual } from 'util';
import {
  RoomAdjustment,
  RoomDefinition,
} from '@home-automation/deep-heating-types';

export function getRoomAdjustments(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomAdjustmentCommands$: Observable<RoomAdjustment>
): Observable<RoomAdjustment> {
  return rooms$.pipe(
    mergeMap((room$) =>
      roomAdjustmentCommands$.pipe(
        filter((roomAdjustment) => roomAdjustment.roomName === room$.key),
        startWith({ roomName: room$.key, adjustment: 0 }),
        distinctUntilChanged<RoomAdjustment>(isDeepStrictEqual),
        shareReplay(1)
      )
    )
  );
}
