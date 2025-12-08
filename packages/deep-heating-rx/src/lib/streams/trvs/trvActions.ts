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
import { Observable, combineLatest } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  map,
  mergeMap,
  share,
  shareReplay,
} from 'rxjs/operators';
import { isDeepStrictEqual } from 'util';
import { TrvDesiredTargetTemperature } from './trvDesiredTargetTemperatures';

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
  if (
    trvControlState.climateEntityId !==
      trvDesiredTargetTemperature.climateEntityId ||
    trvDesiredTargetTemperature.climateEntityId !==
      trvTemperature.climateEntityId ||
    trvTemperature.climateEntityId !==
      trvScheduledTargetTemperature.climateEntityId
  ) {
    return Either.left(
      new MismatchedClimateEntityIds({
        desiredId: trvDesiredTargetTemperature.climateEntityId,
        controlStateId: trvControlState.climateEntityId,
        temperatureId: trvTemperature.climateEntityId,
        scheduledId: trvScheduledTargetTemperature.climateEntityId,
      }),
    );
  }

  if (trvControlState.mode === 'off') return Either.right(null);

  const possibleAction = getTrvAction(
    trvDesiredTargetTemperature.targetTemperature,
  );

  if (possibleAction.mode !== trvControlState.mode)
    return Either.right({
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    });

  if (
    possibleAction.targetTemperature &&
    possibleAction.targetTemperature !== trvControlState.targetTemperature
  )
    return Either.right({
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    });

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
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        combineLatest([
          trvDesiredTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId),
          ),
          trvControlStates.pipe(filter((x) => x.climateEntityId === trvId)),
          trvTemperatures.pipe(filter((x) => x.climateEntityId === trvId)),
          trvScheduledTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId),
          ),
        ]).pipe(
          distinctUntilChanged<
            readonly [
              TrvDesiredTargetTemperature,
              TrvControlState,
              ClimateTemperatureReading,
              TrvScheduledTargetTemperature,
            ]
          >(isDeepStrictEqual),
          filter(([, x]) => x.mode !== 'off'),
        ),
      ),
    ),
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
