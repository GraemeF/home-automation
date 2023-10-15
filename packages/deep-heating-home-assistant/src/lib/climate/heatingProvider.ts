import {
  ClimateEntityId,
  ClimateMode,
  HeatingAction,
  Home,
  HomeAssistantEntity,
  Temperature,
  TrvAction,
} from '@home-automation/deep-heating-types';
import { Effect, Runtime, pipe } from 'effect';
import { Observable, Subject } from 'rxjs';
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
  const heatingActions = new Subject<HeatingAction>();
  const trvActions = new Subject<TrvAction>();

  const setClimate = (
    entityId: ClimateEntityId,
    mode: ClimateMode,
    temperature: Temperature
  ) =>
    pipe(
      Effect.all([
        setClimateEntityMode(entityId, mode),
        setClimateEntityTemperature(entityId, temperature),
      ])
    );

  heatingActions.pipe(debounceTime(5000)).subscribe((action) =>
    pipe(
      setClimate(action.heatingId, action.mode, action.targetTemperature),
      Effect.tap(() =>
        Effect.log(
          `${action.heatingId} has been changed to ${
            (action.mode ?? '', action.targetTemperature ?? '')
          }`
        )
      ),
      Runtime.runPromise(runtime)
    )
  );

  trvActions
    .pipe(
      groupBy((x) => x.climateEntityId),
      mergeMap((x) => x.pipe(debounceTime(5000)))
    )
    .subscribe((action) =>
      pipe(
        setClimate(
          action.climateEntityId,
          action.mode,
          action.targetTemperature
        ),
        Effect.tap(() =>
          Effect.log(
            `${action.climateEntityId} has been changed to ${
              (action.mode ?? '', action.targetTemperature)
            }`
          )
        ),
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
