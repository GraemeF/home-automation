import { Schema } from '@effect/schema';
import {
  ClimateEntityId,
  HassState,
  HeatingAction,
  Home,
  HomeAssistantEntity,
  Temperature,
  TrvAction,
  TrvModeValue,
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

const hiveModeValueToHassState: (mode: TrvModeValue) => HassState = (mode) => {
  switch (mode) {
    case 'SCHEDULE':
      return 'auto';
    case 'MANUAL':
      return 'heat';
    case 'OFF':
      return 'off';
  }
};

export const createHomeAssistantHeatingProvider = (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>,
  runtime: Runtime.Runtime<HomeAssistantApi>
) => {
  const heatingActions = new Subject<HeatingAction>();
  const trvActions = new Subject<TrvAction>();

  const setClimateEntity =
    (runtime: Runtime.Runtime<HomeAssistantApi>) =>
    (
      entityId: ClimateEntityId,
      mode: HassState,
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
        ]),
        Effect.match({
          onSuccess: () => ({ ok: true }),
          onFailure: () => ({ ok: false }),
        }),
        Runtime.runPromise(runtime)
      );

  const setClimate = setClimateEntity(runtime);

  heatingActions
    .pipe(
      debounceTime(5000),
      mergeMap((action) =>
        pipe(
          from(
            setClimate(
              Schema.decodeSync(ClimateEntityId)(action.heatingId),
              hiveModeValueToHassState(action.mode),
              pipe(
                action.targetTemperature,
                Option.fromNullable,
                Option.map(Schema.decodeSync(Temperature))
              )
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
        x.result.ok ? 'has' : 'has not',
        'been changed to',
        x.mode ?? '',
        x.targetTemperature ?? ''
      )
    );

  trvActions
    .pipe(
      groupBy((x) => x.trvId),
      mergeMap((x) => x.pipe(debounceTime(5000))),
      mergeMap((action) =>
        pipe(
          from(
            setClimate(
              Schema.decodeSync(ClimateEntityId)(action.trvId),
              hiveModeValueToHassState(action.mode),
              pipe(
                action.targetTemperature,
                Option.fromNullable,
                Option.map(Schema.decodeSync(Temperature))
              )
            )
          ),
          map((result) => ({
            entityId: action.trvId,
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
        x.result.ok ? 'has' : 'has not',
        'been changed to',
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
