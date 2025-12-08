import {
  ClimateTemperatureReading,
  TrvUpdate,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Observable } from 'rxjs';
import { map, tap } from 'rxjs/operators';

const log = debug('deep-heating:trv-temp-flow');

export const getTrvTemperatures = (
  trvUpdates: Observable<TrvUpdate>,
): Observable<ClimateTemperatureReading> =>
  trvUpdates.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      temperatureReading: x.state.temperature,
    })),
    tap((x) => {
      log(
        '[1-trvTemperatures] %s: %d°C',
        x.climateEntityId,
        x.temperatureReading.temperature,
      );
    }),
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
  );
