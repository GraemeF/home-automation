import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { DateTime } from 'luxon';
import {
  isTrvControlProduct,
  ProductResponse,
  TrvUpdate,
} from '@home-automation/deep-heating-hive';
import { shareReplayLatestByKey } from '@home-automation/rxx';

export const getTrvApiUpdates = (
  p$: Observable<ProductResponse>
): Observable<TrvUpdate> =>
  p$.pipe(
    filter(isTrvControlProduct),
    map((response) => ({
      trvId: response.id,
      name: response.state.name,
      deviceType: response.type,
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
    shareReplayLatestByKey((x) => x.trvId)
  );
