import {
  ClimateTemperatureReading,
  TrvUpdate,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

export function getTrvTemperatures(
  trvUpdates: Observable<TrvUpdate>
): Observable<ClimateTemperatureReading> {
  return trvUpdates.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      temperatureReading: x.state.temperature,
    })),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId)
  );
}
