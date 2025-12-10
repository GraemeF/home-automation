import {
  ClimateAction,
  ClimateEntityId,
  ClimateTemperatureReading,
  OperationalClimateMode,
  Temperature,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
import { Data, Either, Predicate } from 'effect';
import debug from 'debug';
import { Observable, combineLatest } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  map,
  mergeMap,
  share,
  shareReplay,
  tap,
} from 'rxjs/operators';
import { isDeepStrictEqual } from 'util';
import { TrvDesiredTargetTemperature } from './trvDesiredTargetTemperatures';

const log = debug('deep-heating:trv-actions');

export class MismatchedClimateEntityIds extends Data.TaggedError(
  'MismatchedClimateEntityIds',
)<{
  readonly desiredId: ClimateEntityId;
  readonly controlStateId: ClimateEntityId;
  readonly temperatureId: ClimateEntityId;
  readonly scheduledId: ClimateEntityId;
}> {}

function getTrvAction(new_target: Temperature): {
  readonly mode: OperationalClimateMode;
  readonly targetTemperature: Temperature;
} {
  return { mode: 'heat', targetTemperature: new_target };
}

export function determineAction(
  trvDesiredTargetTemperature: Readonly<TrvDesiredTargetTemperature>,
  trvControlState: TrvControlState,
  trvTemperature: ClimateTemperatureReading,
  trvScheduledTargetTemperature: TrvScheduledTargetTemperature,
): Readonly<Either.Either<ClimateAction | null, MismatchedClimateEntityIds>> {
  const trvId = trvControlState.climateEntityId;

  if (
    trvControlState.climateEntityId !==
      trvDesiredTargetTemperature.climateEntityId ||
    trvDesiredTargetTemperature.climateEntityId !==
      trvTemperature.climateEntityId ||
    trvTemperature.climateEntityId !==
      trvScheduledTargetTemperature.climateEntityId
  ) {
    log('[%s] ✗ determineAction: MISMATCHED IDs', trvId);
    return Either.left(
      new MismatchedClimateEntityIds({
        desiredId: trvDesiredTargetTemperature.climateEntityId,
        controlStateId: trvControlState.climateEntityId,
        temperatureId: trvTemperature.climateEntityId,
        scheduledId: trvScheduledTargetTemperature.climateEntityId,
      }),
    );
  }

  if (trvControlState.mode === 'off') {
    log('[%s] ✗ determineAction: mode is OFF', trvId);
    return Either.right(null);
  }

  const possibleAction = getTrvAction(
    trvDesiredTargetTemperature.targetTemperature,
  );

  if (possibleAction.mode !== trvControlState.mode) {
    log(
      '[%s] ✓ determineAction: mode change %s→%s',
      trvId,
      trvControlState.mode,
      possibleAction.mode,
    );
    return Either.right({
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    });
  }

  if (
    possibleAction.targetTemperature &&
    possibleAction.targetTemperature !== trvControlState.targetTemperature
  ) {
    log(
      '[%s] ✓ determineAction: temp change %d→%d',
      trvId,
      trvControlState.targetTemperature,
      possibleAction.targetTemperature,
    );
    return Either.right({
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    });
  }

  log(
    '[%s] ✗ determineAction: no change needed (desired=%d, control=%d)',
    trvId,
    possibleAction.targetTemperature,
    trvControlState.targetTemperature,
  );
  return Either.right(null);
}

export const getTrvActions = (
  trvIds$: Observable<readonly ClimateEntityId[]>,
  trvDesiredTargetTemperatures: Observable<TrvDesiredTargetTemperature>,
  trvControlStates: Observable<TrvControlState>,
  trvTemperatures: Observable<ClimateTemperatureReading>,
  trvScheduledTargetTemperatures: Observable<TrvScheduledTargetTemperature>,
): Observable<ClimateAction> =>
  trvIds$.pipe(
    mergeMap((trvIds) => {
      log('📋 Tracking TRVs: %s', trvIds.join(', '));
      return trvIds.map((trvId) => {
        log('[%s] 🔌 Subscribing to streams...', trvId);
        return combineLatest([
          trvDesiredTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId),
            tap(() => {
              log('[%s] ✓ desiredTarget received', trvId);
            }),
          ),
          trvControlStates.pipe(
            filter((x) => x.climateEntityId === trvId),
            tap(() => {
              log('[%s] ✓ controlState received', trvId);
            }),
          ),
          trvTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId),
            tap(() => {
              log('[%s] ✓ temperature received', trvId);
            }),
          ),
          trvScheduledTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId),
            tap(() => {
              log('[%s] ✓ scheduledTarget received', trvId);
            }),
          ),
        ]).pipe(
          tap(([desired, control, temp, sched]) => {
            log(
              '[%s] ★ combineLatest: desired=%d, control=%s/%d, temp=%d, sched=%d',
              trvId,
              desired.targetTemperature,
              control.mode,
              control.targetTemperature,
              temp.temperatureReading.temperature,
              sched.scheduledTargetTemperature,
            );
          }),
          distinctUntilChanged<
            readonly [
              TrvDesiredTargetTemperature,
              TrvControlState,
              ClimateTemperatureReading,
              TrvScheduledTargetTemperature,
            ]
          >(isDeepStrictEqual),
          tap(([, x]) => {
            if (x.mode === 'off') log('[%s] ✗ FILTERED: mode is off', trvId);
          }),
          filter(([, x]) => x.mode !== 'off'),
        );
      });
    }),
    mergeMap((x) =>
      x.pipe(
        map(
          ([
            trvDesiredTargetTemperature,
            controlState,
            trvTemperature,
            trvScheduledTargetTemperature,
          ]) =>
            determineAction(
              trvDesiredTargetTemperature,
              controlState,
              trvTemperature,
              trvScheduledTargetTemperature,
            ),
        ),
        // Either.left values indicate a bug (mismatched IDs) - filter them out
        // The pipeline design should prevent this, but we handle it gracefully
        filter(Either.isRight),
        map((result) => result.right),
        filter(Predicate.isNotNull),
        shareReplay(1),
      ),
    ),
    share(),
  );
