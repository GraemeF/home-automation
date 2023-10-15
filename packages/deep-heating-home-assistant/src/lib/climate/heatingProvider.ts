import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  ClimateMode,
  HeatingAction,
  Home,
  HomeAssistantEntity,
  Temperature,
  TrvAction,
} from '@home-automation/deep-heating-types';
import debug from 'debug';
import { Effect, Option, Runtime, pipe } from 'effect';
import { Observable, Subject, from } from 'rxjs';
import { debounceTime, groupBy, map, mergeMap } from 'rxjs/operators';
import { HomeAssistantApi } from '../home-assistant-api';
import {
  getClimateEntityUpdates,
  getHeatingApiUpdates,
  getTrvApiUpdates,
  setClimateEntityMode,
  setClimateEntityTemperature,
} from './climate';

const log = debug('home-assistant');

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
    temperature: Option.Option<Temperature>
  ) =>
    pipe(
      Effect.all([
        setClimateEntityMode(entityId, mode),
        pipe(
          temperature,
          Option.match({
            onSome: (temperature) =>
              pipe(setClimateEntityTemperature(entityId, temperature)),
            onNone: () => Effect.unit,
          })
        ),
      ])
    );

  heatingActions
    .pipe(
      debounceTime(5000),
      mergeMap((action) =>
        pipe(
          from(
            pipe(
              setClimate(
                action.heatingId,
                action.mode,
                pipe(action.targetTemperature, Option.fromNullable)
              ),
              Runtime.runPromise(runtime)
            )
          ),
          map((result) => ({
            entityId: action.heatingId,
            mode: action.mode,
            targetTemperature: action.targetTemperature,
            result,
          }))
        )
      )
    )
    .subscribe((x) =>
      log(
        'Heating',
        x.entityId,
        'has been changed to',
        x.mode ?? '',
        x.targetTemperature ?? ''
      )
    );

  trvActions
    .pipe(
      groupBy((x) => x.climateEntityId),
      mergeMap((x) => x.pipe(debounceTime(5000))),
      mergeMap((action) =>
        pipe(
          from(
            pipe(
              setClimate(
                Schema.decodeSync(ClimateEntityId)(action.climateEntityId),
                action.mode,
                pipe(
                  action.targetTemperature,
                  Option.fromNullable,
                  Option.map(Schema.decodeSync(Temperature))
                )
              ),
              Runtime.runPromise(runtime)
            )
          ),
          map((result) => ({
            entityId: action.climateEntityId,
            mode: action.mode,
            targetTemperature: action.targetTemperature,
            result,
          }))
        )
      )
    )
    .subscribe((x) =>
      log(
        'TRV',
        x.entityId,
        'has been changed to',
        x.mode ?? '',
        x.targetTemperature ?? ''
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
