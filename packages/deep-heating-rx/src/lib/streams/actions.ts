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
  filter,
  map,
  mergeAll,
  mergeMap,
  share,
  tap,
  withLatestFrom,
} from 'rxjs/operators';
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
        trvActions.pipe(
          filter((x) => x.climateEntityId === trvId),
          tap((action) =>
            log(
              '[%s] ▶ action received: %s %d',
              trvId,
              action.mode,
              action.targetTemperature,
            ),
          ),
          withLatestFrom(
            trvControlStates$.pipe(
              filter((x) => x.climateEntityId === trvId),
              tap((x) =>
                log(
                  '[%s] ◆ withLatestFrom got controlState: %s/%d',
                  trvId,
                  x.mode,
                  x.targetTemperature,
                ),
              ),
            ),
            trvScheduledTargetTemperatures$.pipe(
              filter((x) => x.climateEntityId === trvId),
              tap((x) =>
                log(
                  '[%s] ◆ withLatestFrom got scheduledTarget: %d',
                  trvId,
                  x.scheduledTargetTemperature,
                ),
              ),
            ),
          ),
          tap(([action]) => {
            log('[%s] ✓ withLatestFrom SUCCESS, publishing action', trvId);
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
