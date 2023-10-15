import { Schema } from '@effect/schema';
import { combineLatest, Observable } from 'rxjs';
import { filter, map, shareReplay } from 'rxjs/operators';
import { HeatingAction, HeatingStatus } from './deep-heating-types';

export function getHeatingActions(
  heatingId: string,
  heatingStatuses: Observable<HeatingStatus>,
  trvsHeating$: Observable<boolean>
): Observable<HeatingAction> {
  return combineLatest([trvsHeating$, heatingStatuses]).pipe(
    filter(([needsHeating, status]) => needsHeating !== status.isHeating),
    map(([needsHeating]) =>
      Schema.parseSync(HeatingAction)(
        needsHeating
          ? {
              heatingId,
              mode: 'heat',
              targetTemperature: 32,
            }
          : { heatingId, mode: 'heat', targetTemperature: 7 }
      )
    ),
    shareReplay(1)
  );
}
