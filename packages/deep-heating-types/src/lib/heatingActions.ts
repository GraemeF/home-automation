import { combineLatest, Observable } from 'rxjs';
import { filter, map, shareReplay } from 'rxjs/operators';
import { HeatingStatus } from './deep-heating-types';
import { Temperature } from './temperature';

export function getHeatingActions(
  heatingId: string,
  heatingStatuses: Observable<HeatingStatus>,
  trvsHeating$: Observable<boolean>
): Observable<HeatingAction> {
  return combineLatest([trvsHeating$, heatingStatuses]).pipe(
    filter(([needsHeating, status]) => needsHeating !== status.isHeating),
    map(([needsHeating]) =>
      needsHeating
        ? ({
            heatingId,
            mode: 'MANUAL',
            targetTemperature: 32,
          } as HeatingAction)
        : ({ heatingId, mode: 'MANUAL', targetTemperature: 7 } as HeatingAction)
    ),
    shareReplay(1)
  );
}

export interface HeatingAction {
  heatingId: string;
  mode: 'MANUAL' | 'SCHEDULE' | 'OFF';
  targetTemperature: Temperature;
}
