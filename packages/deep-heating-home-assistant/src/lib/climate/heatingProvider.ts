import {
  ClimateAction,
  Home,
  HomeAssistantEntity,
} from '@home-automation/deep-heating-types';
import { Effect, Runtime, pipe } from 'effect';
import { Observable, Subject, merge } from 'rxjs';
import { debounceTime, groupBy, mergeMap } from 'rxjs/operators';
import { SetHvacModeError, SetTemperatureError } from '../errors';
import { HomeAssistantApi } from '../home-assistant-api';
import {
  getClimateEntityUpdates,
  getHeatingApiUpdates,
  getTrvApiUpdates,
  setClimateEntityMode,
  setClimateEntityTemperature,
} from './climate';

export const createHomeAssistantHeatingProvider = (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>,
  runtime: Runtime.Runtime<HomeAssistantApi>,
) => {
  const heatingActions = new Subject<ClimateAction>();
  const trvActions = new Subject<ClimateAction>();

  merge(
    trvActions.pipe(
      groupBy((x) => x.climateEntityId),
      mergeMap((x) => x.pipe(debounceTime(5000))),
    ),
    heatingActions.pipe(debounceTime(5000)),
  ).subscribe((action) => {
    void pipe(
      [
        setClimateEntityMode(action.climateEntityId, action.mode),
        setClimateEntityTemperature(
          action.climateEntityId,
          action.targetTemperature,
        ),
      ],
      Effect.all,
      Effect.tap(() =>
        Effect.log(
          `${action.climateEntityId} has been changed to ${action.mode} ${String(action.targetTemperature)}`,
        ),
      ),
      Effect.catchTag(
        'SetTemperatureError',
        (error: Readonly<SetTemperatureError>) =>
          Effect.logError(
            `Failed to set temperature for ${error.entityId} to ${String(error.targetTemperature)}`,
          ),
      ),
      Effect.catchTag('SetHvacModeError', (error: Readonly<SetHvacModeError>) =>
        Effect.logError(
          `Failed to set HVAC mode for ${error.entityId} to ${error.mode}`,
        ),
      ),
      Effect.as('done'),
      Runtime.runPromise(runtime),
    );
  });

  const climateEntityUpdates$ = getClimateEntityUpdates(entityUpdates$);
  const trvApiUpdatesForHome = getTrvApiUpdates(home);
  return {
    trvActions,
    heatingActions,
    trvApiUpdates$: trvApiUpdatesForHome(climateEntityUpdates$),
    heatingApiUpdates$: getHeatingApiUpdates(climateEntityUpdates$),
  };
};
