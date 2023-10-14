import { RoomDecisionPoint } from '@home-automation/deep-heating-types';
import { HashSet, pipe } from 'effect';
import { Observable } from 'rxjs';
import { scan, shareReplay } from 'rxjs/operators';

export const getRoomsHeating = (
  roomStatuses$: Observable<RoomDecisionPoint>
): Observable<HashSet.HashSet<string>> =>
  roomStatuses$.pipe(
    scan(
      (heatingRooms, { roomName, targetTemperature, temperature }) =>
        pipe(
          heatingRooms,
          targetTemperature > temperature
            ? HashSet.add(roomName)
            : HashSet.remove(roomName)
        ),
      HashSet.empty<string>()
    ),
    shareReplay(1)
  );
