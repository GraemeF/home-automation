import { parseHueTime } from '@home-automation/deep-heating-hue';
import {
  RoomSensors,
  RoomTemperature,
  TemperatureSensorUpdate,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap, share } from 'rxjs/operators';

export const getRoomTemperatures = (
  roomSensors$: Observable<Observable<RoomSensors>>,
  temperatureSensorUpdate$: Observable<TemperatureSensorUpdate>
): Observable<RoomTemperature> =>
  roomSensors$.pipe(
    mergeMap((roomSensors$) =>
      combineLatest([roomSensors$, temperatureSensorUpdate$]).pipe(
        filter(([roomSensors, temperatureSensorUpdate]) => {
          return roomSensors.temperatureSensorIds.includes(
            temperatureSensorUpdate.uniqueid
          );
        }),
        map(([roomSensors, temperatureSensorUpdate]) => {
          return {
            roomName: roomSensors.roomName,
            temperatureReading: {
              temperature: temperatureSensorUpdate.state.temperature / 100.0,
              time: parseHueTime(temperatureSensorUpdate.state.lastupdated),
            },
          };
        }),
        shareReplayLatestDistinctByKey((x) => x.roomName)
      )
    ),
    share()
  );
