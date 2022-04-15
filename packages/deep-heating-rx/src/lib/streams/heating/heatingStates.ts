import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { DateTime } from 'luxon';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import {
  HeatingUpdate,
  isHeatingProduct,
  ProductResponse,
} from '@home-automation/deep-heating-hive';

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
