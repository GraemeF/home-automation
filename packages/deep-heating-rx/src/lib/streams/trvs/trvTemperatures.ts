import { map } from 'rxjs/operators';
import { Observable } from 'rxjs';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { TrvTemperature } from '@home-automation/deep-heating-types';
import { TrvUpdate } from '@home-automation/deep-heating-hive';

export function getTrvTemperatures(
  trvUpdates: Observable<TrvUpdate>
): Observable<TrvTemperature> {
  return trvUpdates.pipe(
    map((x) => ({
      trvId: x.trvId,
      temperatureReading: x.state.temperature,
    })),
    shareReplayLatestDistinctByKey((x) => x.trvId)
  );
}
