import { Schema } from 'effect';
import { combineLatest, Observable } from 'rxjs';
import { filter, map, shareReplay } from 'rxjs/operators';
import { ClimateAction, HeatingStatus } from './deep-heating-types';
import { ClimateEntityId } from './entities';
import { OperationalClimateMode } from './home-assistant';
import { Temperature } from './temperature';

const Heat = Schema.decodeUnknownSync(OperationalClimateMode)('heat');
const On = Schema.decodeUnknownSync(Temperature)(32);
const Off = Schema.decodeUnknownSync(Temperature)(7);

export const getHeatingActions = (
  heatingId: ClimateEntityId,
  heatingStatuses: Observable<HeatingStatus>,
  trvsHeating$: Observable<boolean>,
): Observable<ClimateAction> =>
  combineLatest([trvsHeating$, heatingStatuses]).pipe(
    filter(([needsHeating, status]) => needsHeating !== status.isHeating),
    map(([needsHeating]) => ({
      climateEntityId: heatingId,
      mode: Heat,
      targetTemperature: needsHeating ? On : Off,
    })),
    shareReplay(1),
  );
