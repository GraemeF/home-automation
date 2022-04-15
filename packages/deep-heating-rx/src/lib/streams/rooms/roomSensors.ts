import { filter, map } from 'rxjs/operators';
import { GroupedObservable, Observable } from 'rxjs';
import { isNotNull } from '../filters';
import {
  RoomDefinition,
  RoomSensors,
  SensorUpdate,
  SwitchSensorUpdate,
  TemperatureSensorUpdate,
} from '@home-automation/deep-heating-types';

export function isTemperatureSensorUpdate(
  input: SensorUpdate
): input is TemperatureSensorUpdate {
  return input.type === 'ZLLTemperature';
}

export function isSwitchSensorUpdate(
  input: SensorUpdate
): input is SwitchSensorUpdate {
  return input.type === 'ZLLSwitch';
}

export function getRoomSensors(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>
): Observable<Observable<RoomSensors>> {
  return rooms$.pipe(
    map((room$) =>
      room$.pipe(
        map((roomDefinition) => roomDefinition.temperatureSensorId),
        filter(isNotNull),
        map((temperatureSensorId) => ({
          roomName: room$.key,
          temperatureSensorIds: [temperatureSensorId],
        }))
      )
    )
  );
}
