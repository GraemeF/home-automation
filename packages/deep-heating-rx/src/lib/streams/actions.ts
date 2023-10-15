import { Schema } from '@effect/schema';
import {
  HeatingAction,
  HeatingStatus,
  Temperature,
  TrvAction,
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
  trvActions: Observable<TrvAction>
): Observable<GroupedObservable<string, TrvAction>> {
  return trvActions.pipe(groupBy((x) => x.climateEntityId));
}

function getNextTrvControlState(
  latest: TrvControlState,
  action: TrvAction,
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

function getNextHeatingStatus(action: HeatingAction): HeatingStatus {
  return {
    heatingId: action.heatingId,
    isHeating: action.targetTemperature > 20,
    source: 'Synthesised',
  };
}

export function applyTrvActions(
  trvIds$: Observable<string[]>,
  trvActions: Observable<TrvAction>,
  trvControlStates$: Observable<TrvControlState>,
  trvScheduledTargetTemperatures$: Observable<TrvScheduledTargetTemperature>,
  publishHiveTrvAction: (action: TrvAction) => void
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
  heatingActions$: Observable<HeatingAction>,
  publishHiveHeatingAction: (action: HeatingAction) => void
): Observable<HeatingStatus> {
  return heatingActions$.pipe(
    tap((action) => publishHiveHeatingAction(action)),
    map((action) => getNextHeatingStatus(action))
  );
}
