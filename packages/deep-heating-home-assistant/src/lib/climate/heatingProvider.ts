import {
  ClimateAction,
  Home,
  HomeAssistantEntity,
} from '@home-automation/deep-heating-types';
import { Effect, Runtime, pipe } from 'effect';
import { Observable, Subject, merge } from 'rxjs';
import { debounceTime, groupBy, mergeMap } from 'rxjs/operators';
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
  runtime: Runtime.Runtime<HomeAssistantApi>
) => {
  const heatingActions = new Subject<ClimateAction>();
  const trvActions = new Subject<ClimateAction>();

  merge(
    trvActions.pipe(
      groupBy((x) => x.climateEntityId),
      mergeMap((x) => x.pipe(debounceTime(5000)))
    ),
    heatingActions.pipe(debounceTime(5000))
  ).subscribe((action) =>
    pipe(
      [
        setClimateEntityMode(action.climateEntityId, action.mode),
        setClimateEntityTemperature(
          action.climateEntityId,
          action.targetTemperature
        ),
      ],
      Effect.all,
      Effect.tapBoth({
        onSuccess: () =>
          Effect.log(
            `${action.climateEntityId} has been changed to ${
              (action.mode ?? '', action.targetTemperature)
            }`
          ),
        onFailure: () =>
          Effect.logError(
            `Failed to change ${action.climateEntityId} to ${
              (action.mode ?? '', action.targetTemperature)
            }`
          ),
      }),
      Effect.sandbox,
      Effect.catchAll(Effect.logError),
      Effect.as('done'),
      Runtime.runPromise(runtime)
    )
  );

  const climateEntityUpdates$ = getClimateEntityUpdates(entityUpdates$);
  return {
    trvActions,
    heatingActions,
    trvApiUpdates$: getTrvApiUpdates(home)(climateEntityUpdates$),
    heatingApiUpdates$: getHeatingApiUpdates(climateEntityUpdates$),
  };
};
