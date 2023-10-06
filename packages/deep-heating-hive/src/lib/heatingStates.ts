import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { DateTime } from 'luxon';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { ProductResponse } from './hive-api';
import { isHeatingProduct } from './hive';
import { HeatingUpdate } from '@home-automation/deep-heating-types';

export const getHeatingApiUpdates = (
  p$: Observable<ProductResponse>
): Observable<HeatingUpdate> =>
  p$.pipe(
    filter(isHeatingProduct),
    map((response) => ({
      heatingId: response.id,
      name: response.state.name,
      state: {
        temperature: {
          temperature: response.props.temperature,
          time: DateTime.local(),
        },
        target: response.state.target,
        mode: response.state.mode,
        isHeating: response.props.working,
        schedule: response.state.schedule,
      },
    })),
    shareReplayLatestDistinctByKey((x) => x.heatingId)
  );
