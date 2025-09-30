import {
  ClimateEntityId,
  ClimateEntityStatus,
} from '@home-automation/deep-heating-types';
import { HashSet, pipe } from 'effect';
import { Observable } from 'rxjs';
import { distinctUntilChanged, map, scan, shareReplay } from 'rxjs/operators';

export const getTrvsHeating = (
  trvStatuses$: Observable<ClimateEntityStatus>,
): Observable<HashSet.HashSet<ClimateEntityId>> =>
  trvStatuses$.pipe(
    scan(
      (heatingTrvs, { isHeating, climateEntityId }) =>
        pipe(
          heatingTrvs,
          isHeating
            ? HashSet.add(climateEntityId)
            : HashSet.remove(climateEntityId),
        ),
      HashSet.empty<ClimateEntityId>(),
    ),
    shareReplay(1),
  );

export const getAnyHeating = <T>(
  heatingThings: Observable<HashSet.HashSet<T>>,
): Observable<boolean> =>
  heatingThings.pipe(
    map(HashSet.size),
    map((size) => size > 0),
    distinctUntilChanged((a, b) => a === b),
    shareReplay(1),
  );
