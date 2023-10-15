import { Schema } from '@effect/schema';
import {
  ClimateAction,
  HeatingStatus,
  Temperature,
  TrvControlState,
  TrvScheduledTargetTemperature,
} from '@home-automation/deep-heating-types';
import { GroupedObservable, Observable } from 'rxjs';
import {
  filter,
  groupBy,
  map,
  mergeAll,
  mergeMap,
  share,
  tap,
  withLatestFrom,
} from 'rxjs/operators';

export function getTrvActionsByTrvId(
  trvActions: Observable<ClimateAction>
): Observable<GroupedObservable<string, ClimateAction>> {
  return trvActions.pipe(groupBy((x) => x.climateEntityId));
}

function getNextTrvControlState(
  latest: TrvControlState,
  action: ClimateAction,
  scheduledTargetTemperature: TrvScheduledTargetTemperature
): TrvControlState {
  const mode = action.mode ?? latest.mode;

  function getTargetTemperature() {
    switch (mode) {
      case 'off':
        return Schema.parseSync(Temperature)(7);
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
}

function getNextHeatingStatus(action: ClimateAction): HeatingStatus {
  return {
    heatingId: action.climateEntityId,
    isHeating: action.targetTemperature > 20,
    source: 'Synthesised',
  };
}

export function applyTrvActions(
  trvIds$: Observable<string[]>,
  trvActions: Observable<ClimateAction>,
  trvControlStates$: Observable<TrvControlState>,
  trvScheduledTargetTemperatures$: Observable<TrvScheduledTargetTemperature>,
  publishHiveTrvAction: (action: ClimateAction) => void
): Observable<TrvControlState> {
  return trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        trvActions.pipe(
          filter((x) => x.climateEntityId === trvId),
          withLatestFrom(
            trvControlStates$.pipe(filter((x) => x.climateEntityId === trvId)),
            trvScheduledTargetTemperatures$.pipe(
              filter((x) => x.climateEntityId === trvId)
            )
          ),
          tap(([action]) => publishHiveTrvAction(action)),
          map(([action, latest, scheduledTargetTemperature]) =>
            getNextTrvControlState(latest, action, scheduledTargetTemperature)
          )
        )
      )
    ),
    mergeAll(),
    share()
  );
}

export function applyHeatingActions(
  heatingActions$: Observable<ClimateAction>,
  publishHiveHeatingAction: (action: ClimateAction) => void
): Observable<HeatingStatus> {
  return heatingActions$.pipe(
    tap((action) => publishHiveHeatingAction(action)),
    map((action) => getNextHeatingStatus(action))
  );
}
