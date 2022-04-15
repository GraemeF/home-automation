import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import {
  RoomStatus,
  RoomTrvStatuses,
} from '@home-automation/deep-heating-types';

export function getRoomStatuses(
  roomTrvStatuses$: Observable<RoomTrvStatuses>
): Observable<RoomStatus> {
  return roomTrvStatuses$.pipe(
    map((roomTrvStatuses) => ({
      roomName: roomTrvStatuses.roomName,
      isHeating: roomTrvStatuses.trvStatuses.some((x) => x.isHeating),
    })),
    shareReplayLatestDistinctByKey((x) => x.roomName)
  );
}
