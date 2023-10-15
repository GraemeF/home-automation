import { Schema } from '@effect/schema';
import { combineLatest, Observable } from 'rxjs';
import { filter, map, shareReplay } from 'rxjs/operators';
import { ClimateAction, HeatingStatus } from './deep-heating-types';
import { ClimateEntityId } from './entities';
import { ClimateMode } from './home-assistant';
import { Temperature } from './temperature';

const Heat = Schema.parseSync(ClimateMode)('heat');
const On = Schema.parseSync(Temperature)(32);
const Off = Schema.parseSync(Temperature)(7);

export function getHeatingActions(
  heatingId: ClimateEntityId,
  heatingStatuses: Observable<HeatingStatus>,
  trvsHeating$: Observable<boolean>
): Observable<ClimateAction> {
  return combineLatest([trvsHeating$, heatingStatuses]).pipe(
    filter(([needsHeating, status]) => needsHeating !== status.isHeating),
    map(([needsHeating]) => ({
      climateEntityId: heatingId,
      mode: Heat,
      targetTemperature: needsHeating ? On : Off,
    })),
    shareReplay(1)
  );
}
