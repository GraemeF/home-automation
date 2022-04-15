import { Observable } from 'rxjs';
import { scan, shareReplay } from 'rxjs/operators';
import { RoomDecisionPoint } from '@home-automation/deep-heating-types';

export const getRoomsHeating = (
  roomStatuses$: Observable<RoomDecisionPoint>
): Observable<Set<string>> =>
  roomStatuses$.pipe(
    scan((heatingRooms, { roomName, targetTemperature, temperature }) => {
      if (targetTemperature > temperature) {
        return heatingRooms.add(roomName);
      } else {
        heatingRooms.delete(roomName);
        return heatingRooms;
      }
    }, new Set<string>()),
    shareReplay(1)
  );
