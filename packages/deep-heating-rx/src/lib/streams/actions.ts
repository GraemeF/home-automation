import {
  ClimateAction,
  HeatingStatus,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
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

  function getTargetTemperature() {
    switch (mode) {
      case 'off':
        return MinimumTrvTargetTemperature;
      case 'heat':
        return action.targetTemperature ?? latest.targetTemperature;
      case 'auto':
        return scheduledTargetTemperature.scheduledTargetTemperature;
    }
  }

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
  trvIds$: Observable<string[]>,
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
    tap((action) => publishHiveHeatingAction(action)),
    map((action) => getNextHeatingStatus(action)),
  );
