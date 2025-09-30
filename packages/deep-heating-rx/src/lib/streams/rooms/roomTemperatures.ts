import {
  RoomSensors,
  RoomTemperature,
  TemperatureSensorEntity,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap, share } from 'rxjs/operators';

export const getRoomTemperatures = (
  roomSensors$: Observable<Observable<RoomSensors>>,
  temperatureSensorUpdate$: Observable<TemperatureSensorEntity>,
): Observable<RoomTemperature> =>
  roomSensors$.pipe(
    mergeMap((roomSensors$) =>
      combineLatest([roomSensors$, temperatureSensorUpdate$]).pipe(
        filter(([roomSensors, temperatureSensorUpdate]) => {
          return roomSensors.temperatureSensorIds.includes(
            temperatureSensorUpdate.entity_id,
          );
        }),
        map(([roomSensors, temperatureSensorUpdate]) => {
          return {
            roomName: roomSensors.roomName,
            temperatureReading: {
              temperature: temperatureSensorUpdate.state,
              time: temperatureSensorUpdate.last_updated,
            },
          };
        }),
        shareReplayLatestDistinctByKey((x) => x.roomName),
      ),
    ),
    share(),
  );
