import { combineLatest, Observable } from 'rxjs';
import { filter, map, shareReplay } from 'rxjs/operators';
import { HeatingStatus } from './deep-heating-types';

export function getHeatingActions(
  heatingId: string,
  heatingStatuses: Observable<HeatingStatus>,
  trvsHeating$: Observable<boolean>
): Observable<HeatingAction> {
  return combineLatest([trvsHeating$, heatingStatuses]).pipe(
    filter(([needsHeating, status]) => needsHeating !== status.isHeating),
    map(([needsHeating]) =>
      needsHeating
        ? { heatingId, mode: 'MANUAL', targetTemperature: 32 }
        : { heatingId, mode: 'MANUAL', targetTemperature: 7 }
    ),
    shareReplay(1)
  );
}

export interface HeatingAction {
  heatingId: string;
  mode: string;
  targetTemperature: number;
}
