import {
  ClimateAction,
  HeatingStatus,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
import debug from 'debug';
import { Match } from 'effect';
import { Observable } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  map,
  mergeAll,
  mergeMap,
  share,
  tap,
} from 'rxjs/operators';
import { combineLatest } from 'rxjs';
import { MinimumTrvTargetTemperature } from './trvs/trvDecisionPoints';

const log = debug('deep-heating:apply-actions');

const getNextTrvControlState = (
  latest: TrvControlState,
  action: ClimateAction,
  scheduledTargetTemperature: TrvScheduledTargetTemperature,
): TrvControlState => {
  const mode = action.mode;

  const getTargetTemperature = () =>
    Match.value(mode).pipe(
      Match.when('off', () => MinimumTrvTargetTemperature),
      Match.when('heat', () => action.targetTemperature),
      Match.when(
        'auto',
        () => scheduledTargetTemperature.scheduledTargetTemperature,
      ),
      Match.exhaustive,
    );

  return {
    climateEntityId: latest.climateEntityId,
    mode: mode,
    targetTemperature: getTargetTemperature(),
    source: 'Synthesised',
  };
};

const getNextHeatingStatus = (action: ClimateAction): HeatingStatus => ({
  heatingId: action.climateEntityId,
  isHeating: action.targetTemperature > 20,
  source: 'Synthesised',
});

export const applyTrvActions = (
  trvIds$: Observable<readonly string[]>,
  trvActions: Observable<ClimateAction>,
  trvControlStates$: Observable<TrvControlState>,
  trvScheduledTargetTemperatures$: Observable<TrvScheduledTargetTemperature>,
  publishHiveTrvAction: (action: ClimateAction) => void,
): Observable<TrvControlState> =>
  trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        // Use combineLatest instead of withLatestFrom to avoid race condition
        // at startup where actions could be dropped if the secondary streams
        // hadn't emitted yet. combineLatest waits for ALL streams to emit.
        combineLatest([
          trvActions.pipe(filter((x) => x.climateEntityId === trvId)),
          trvControlStates$.pipe(filter((x) => x.climateEntityId === trvId)),
          trvScheduledTargetTemperatures$.pipe(
            filter((x) => x.climateEntityId === trvId),
          ),
        ]).pipe(
          // Only emit when the action changes (not when control state updates)
          distinctUntilChanged(
            ([prevAction], [currAction]) =>
              prevAction.mode === currAction.mode &&
              prevAction.targetTemperature === currAction.targetTemperature,
          ),
          tap(([action]) => {
            log(
              '[%s] ▶ action received: %s %d',
              trvId,
              action.mode,
              action.targetTemperature,
            );
            log('[%s] ✓ combineLatest ready, publishing action', trvId);
            publishHiveTrvAction(action);
          }),
          map(([action, latest, scheduledTargetTemperature]) =>
            getNextTrvControlState(latest, action, scheduledTargetTemperature),
          ),
        ),
      ),
    ),
    mergeAll(),
    share(),
  );

export const applyHeatingActions = (
  heatingActions$: Observable<ClimateAction>,
  publishHiveHeatingAction: (action: ClimateAction) => void,
): Observable<HeatingStatus> =>
  heatingActions$.pipe(
    tap(publishHiveHeatingAction),
    map(getNextHeatingStatus),
  );
