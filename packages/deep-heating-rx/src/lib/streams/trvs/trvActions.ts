import { combineLatest, Observable } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  map,
  mergeMap,
  share,
  shareReplay,
} from 'rxjs/operators';
import { TrvDesiredTargetTemperature } from './trvDesiredTargetTemperatures';
import { isDeepStrictEqual } from 'util';
import {
  TrvAction,
  TrvControlState,
  TrvModeValue,
  TrvScheduledTargetTemperature,
  TrvTemperature,
} from '@home-automation/deep-heating-types';
import { Predicate } from 'effect';

function getTrvAction(
  new_target: number,
  schedule_target: number,
  trv_current: number
): { mode: TrvModeValue; targetTemperature?: number } {
  if (new_target <= schedule_target && schedule_target <= trv_current)
    return { mode: 'SCHEDULE' };

  if (new_target >= schedule_target && schedule_target >= trv_current)
    return { mode: 'SCHEDULE' };

  return { mode: 'MANUAL', targetTemperature: new_target };
}

export function determineAction(
  trvDesiredTargetTemperature: TrvDesiredTargetTemperature,
  trvControlState: TrvControlState,
  trvTemperature: TrvTemperature,
  trvScheduledTargetTemperature: TrvScheduledTargetTemperature
): TrvAction | null {
  if (
    trvControlState.trvId !== trvDesiredTargetTemperature.trvId ||
    trvDesiredTargetTemperature.trvId !== trvTemperature.trvId ||
    trvTemperature.trvId !== trvScheduledTargetTemperature.trvId
  )
    throw Error('mismatched trvIds');

  if (trvControlState.mode === 'OFF') return null;

  const possibleAction = getTrvAction(
    trvDesiredTargetTemperature.targetTemperature,
    trvScheduledTargetTemperature.scheduledTargetTemperature,
    trvTemperature.temperatureReading.temperature
  );

  if (possibleAction.mode !== trvControlState.mode)
    return { trvId: trvControlState.trvId, ...possibleAction };

  if (
    possibleAction.targetTemperature &&
    possibleAction.targetTemperature !== trvControlState.targetTemperature
  )
    return { trvId: trvControlState.trvId, ...possibleAction };

  return null;
}

export function getTrvActions(
  trvIds$: Observable<string[]>,
  trvDesiredTargetTemperatures: Observable<TrvDesiredTargetTemperature>,
  trvControlStates: Observable<TrvControlState>,
  trvTemperatures: Observable<TrvTemperature>,
  trvScheduledTargetTemperatures: Observable<TrvScheduledTargetTemperature>
): Observable<TrvAction> {
  return trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        combineLatest([
          trvDesiredTargetTemperatures.pipe(filter((x) => x.trvId === trvId)),
          trvControlStates.pipe(filter((x) => x.trvId === trvId)),
          trvTemperatures.pipe(filter((x) => x.trvId === trvId)),
          trvScheduledTargetTemperatures.pipe(filter((x) => x.trvId === trvId)),
        ]).pipe(
          distinctUntilChanged<
            [
              TrvDesiredTargetTemperature,
              TrvControlState,
              TrvTemperature,
              TrvScheduledTargetTemperature
            ]
          >(isDeepStrictEqual),
          filter(([, x]) => x.mode !== 'OFF')
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
}
