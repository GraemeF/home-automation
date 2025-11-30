import {
  RoomAdjustment,
  RoomDefinition,
} from '@home-automation/deep-heating-types';
import { GroupedObservable, Observable } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  mergeMap,
  shareReplay,
  startWith,
} from 'rxjs/operators';
import { isDeepStrictEqual } from 'util';

export const getRoomAdjustments = (
  initialRoomAdjustments: readonly RoomAdjustment[],
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  roomAdjustmentCommands$: Observable<RoomAdjustment>,
): Observable<RoomAdjustment> =>
  rooms$.pipe(
    mergeMap((room$) =>
      roomAdjustmentCommands$.pipe(
        filter((roomAdjustment) => roomAdjustment.roomName === room$.key),
        startWith({
          roomName: room$.key,
          adjustment:
            initialRoomAdjustments.find((x) => x.roomName === room$.key)
              ?.adjustment ?? 0,
        }),
        distinctUntilChanged<RoomAdjustment>(isDeepStrictEqual),
        shareReplay(1),
      ),
    ),
  );
