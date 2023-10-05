import { from, Observable, timer } from 'rxjs';
import { getClimateEntities } from './home-assistant-api';
import { shareReplay, switchMap, throttleTime } from 'rxjs/operators';
import { ClimateEntity } from './schema';
import { Effect, pipe } from 'effect';

const refreshIntervalSeconds = 60 * 1000;

export const getClimateEntityUpdates = (): Observable<ClimateEntity> =>
  timer(0, refreshIntervalSeconds).pipe(
    throttleTime(refreshIntervalSeconds),
    switchMap(() => from(pipe(getClimateEntities, Effect.runSync))),
    shareReplay(1)
  );
