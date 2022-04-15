import { from, GroupedObservable, Observable, timer } from 'rxjs';
import {
  groupBy,
  map,
  mergeAll,
  mergeMap,
  shareReplay,
  switchMap,
} from 'rxjs/operators';
import { getSensors } from './hue-api';
import { SensorUpdate } from '@home-automation/deep-heating-types';
import { Dictionary } from '@home-automation/dictionary';
import { shareReplayLatestDistinct } from '@home-automation/rxx';

function splitIntoDevices(
  sensors: Dictionary<string, SensorUpdate>
): SensorUpdate[] {
  return Object.entries(sensors).map(([, value]) => value);
}

export function getHueSensorUpdates(): Observable<SensorUpdate> {
  return getSensorStreams().pipe(
    mergeMap((sensor$) =>
      sensor$.pipe(
        shareReplayLatestDistinct(
          (x, y) => x.state.lastupdated === y.state.lastupdated
        )
      )
    )
  );
}

function getSensorStreams(): Observable<
  GroupedObservable<string, SensorUpdate>
> {
  return timer(0, 15 * 1000).pipe(
    shareReplay(1),
    switchMap(() => from(getSensors())),
    map((sensors) => splitIntoDevices(sensors)),
    mergeAll(),
    groupBy((x) => x.uniqueid),
    shareReplay(1)
  );
}
