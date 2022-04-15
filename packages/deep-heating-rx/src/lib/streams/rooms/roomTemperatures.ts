import { combineLatest, Observable } from 'rxjs';
import { filter, map, mergeMap, share } from 'rxjs/operators';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import {
  RoomSensors,
  RoomTemperature,
  TemperatureSensorUpdate,
} from '@home-automation/deep-heating-types';
import { parseHueTime } from '@home-automation/deep-heating-hue';

export const getRoomTemperatures = (
  roomSensors$: Observable<Observable<RoomSensors>>,
  temperatureSensorUpdate$: Observable<TemperatureSensorUpdate>
): Observable<RoomTemperature> =>
  roomSensors$.pipe(
    mergeMap((roomSensors$) =>
      combineLatest([roomSensors$, temperatureSensorUpdate$]).pipe(
        filter(([roomSensors, temperatureSensorUpdate]) =>
          roomSensors.temperatureSensorIds.includes(
            temperatureSensorUpdate.uniqueid
          )
        ),
        map(([roomSensors, temperatureSensorUpdate]) => ({
          roomName: roomSensors.roomName,
          temperatureReading: {
            temperature: temperatureSensorUpdate.state.temperature / 100.0,
            time: parseHueTime(temperatureSensorUpdate.state.lastupdated),
          },
        })),
        shareReplayLatestDistinctByKey((x) => x.roomName)
      )
    ),
    share()
  );
