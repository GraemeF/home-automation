import { TrvStatus } from '@home-automation/deep-heating-types';
import { Observable } from 'rxjs';
import { distinctUntilChanged, map, scan, shareReplay } from 'rxjs/operators';

export const getTrvsHeating = (
  trvStatuses$: Observable<TrvStatus>
): Observable<Set<string>> =>
  trvStatuses$.pipe(
    scan((heatingTrvs, { isHeating, climateEntityId }) => {
      if (isHeating) {
        return heatingTrvs.add(climateEntityId);
      } else {
        heatingTrvs.delete(climateEntityId);
        return heatingTrvs;
      }
    }, new Set<string>()),
    shareReplay(1)
  );

export const getAnyHeating = (
  heatingThings: Observable<Set<string>>
): Observable<boolean> =>
  heatingThings.pipe(
    map((heatingThings) => heatingThings.size > 0),
    distinctUntilChanged((a, b) => a === b),
    shareReplay(1)
  );
