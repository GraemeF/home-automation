import {
  ClimateAction,
  HeatingStatus,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
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

const getNextTrvControlState = (
  latest: TrvControlState,
  action: ClimateAction,
  scheduledTargetTemperature: TrvScheduledTargetTemperature,
): TrvControlState => {
  const mode = action.mode ?? latest.mode;

  const getTargetTemperature = () =>
    Match.value(mode).pipe(
      Match.when('off', () => MinimumTrvTargetTemperature),
      Match.when(
        'heat',
        () => action.targetTemperature ?? latest.targetTemperature,
      ),
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
          withLatestFrom(
            trvControlStates$.pipe(filter((x) => x.climateEntityId === trvId)),
            trvScheduledTargetTemperatures$.pipe(
              filter((x) => x.climateEntityId === trvId),
            ),
          ),
          tap(([action]) => publishHiveTrvAction(action)),
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
