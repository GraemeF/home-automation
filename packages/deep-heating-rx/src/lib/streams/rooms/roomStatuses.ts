import {
  RoomStatus,
  RoomTrvStatuses,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export const getRoomStatuses = (
  roomTrvStatuses$: Observable<RoomTrvStatuses>
): Observable<RoomStatus> =>
  roomTrvStatuses$.pipe(
    map((roomTrvStatuses) => ({
      roomName: roomTrvStatuses.roomName,
      isHeating: roomTrvStatuses.trvStatuses.some((x) => x.isHeating),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName)
  );
