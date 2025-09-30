import {
  RoomDefinition,
  RoomSensors,
} from '@home-automation/deep-heating-types';
import { Option, pipe } from 'effect';
import { isNotNull } from 'effect/Predicate';
import { GroupedObservable, Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';

export const getRoomSensors = (
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
): Observable<Observable<RoomSensors>> =>
  rooms$.pipe(
    map((room$) =>
      room$.pipe(
        map((roomDefinition) =>
          pipe(
            roomDefinition.temperatureSensorEntityId,
            Option.map((temperatureSensorId) => ({
              roomName: room$.key,
              temperatureSensorIds: [temperatureSensorId],
            })),
            Option.getOrNull,
          ),
        ),
        filter(isNotNull),
      ),
    ),
  );
