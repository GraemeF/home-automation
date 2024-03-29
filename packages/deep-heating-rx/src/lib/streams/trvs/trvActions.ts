import {
  ClimateAction,
  ClimateEntityId,
  ClimateMode,
  ClimateTemperatureReading,
  Temperature,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
import { Predicate } from 'effect';
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

function getTrvAction(new_target: Temperature): {
  mode: ClimateMode;
  targetTemperature: Temperature;
} {
  return { mode: 'heat', targetTemperature: new_target };
}

export function determineAction(
  trvDesiredTargetTemperature: TrvDesiredTargetTemperature,
  trvControlState: TrvControlState,
  trvTemperature: ClimateTemperatureReading,
  trvScheduledTargetTemperature: TrvScheduledTargetTemperature
): ClimateAction | null {
  if (
    trvControlState.climateEntityId !==
      trvDesiredTargetTemperature.climateEntityId ||
    trvDesiredTargetTemperature.climateEntityId !==
      trvTemperature.climateEntityId ||
    trvTemperature.climateEntityId !==
      trvScheduledTargetTemperature.climateEntityId
  )
    throw Error('mismatched climateEntityIds');

  if (trvControlState.mode === 'off') return null;

  const possibleAction = getTrvAction(
    trvDesiredTargetTemperature.targetTemperature
  );

  if (possibleAction.mode !== trvControlState.mode)
    return {
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    };

  if (
    possibleAction.targetTemperature &&
    possibleAction.targetTemperature !== trvControlState.targetTemperature
  )
    return {
      climateEntityId: trvControlState.climateEntityId,
      ...possibleAction,
    };

  return null;
}

export const getTrvActions = (
  trvIds$: Observable<ClimateEntityId[]>,
  trvDesiredTargetTemperatures: Observable<TrvDesiredTargetTemperature>,
  trvControlStates: Observable<TrvControlState>,
  trvTemperatures: Observable<ClimateTemperatureReading>,
  trvScheduledTargetTemperatures: Observable<TrvScheduledTargetTemperature>
): Observable<ClimateAction> =>
  trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        combineLatest([
          trvDesiredTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId)
          ),
          trvControlStates.pipe(filter((x) => x.climateEntityId === trvId)),
          trvTemperatures.pipe(filter((x) => x.climateEntityId === trvId)),
          trvScheduledTargetTemperatures.pipe(
            filter((x) => x.climateEntityId === trvId)
          ),
        ]).pipe(
          distinctUntilChanged<
            [
              TrvDesiredTargetTemperature,
              TrvControlState,
              ClimateTemperatureReading,
              TrvScheduledTargetTemperature
            ]
          >(isDeepStrictEqual),
          filter(([, x]) => x.mode !== 'off')
        )
      )
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
              trvScheduledTargetTemperature
            )
        ),
        filter(Predicate.isNotNull),
        shareReplay(1)
      )
    ),
    share()
  );
