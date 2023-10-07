import {
  HeatingAction,
  HeatingProvider,
  Temperature,
  TrvAction,
  TrvModeValue,
} from '@home-automation/deep-heating-types';
import debug from 'debug';
import { debounceTime, groupBy, mergeMap, map } from 'rxjs/operators';
import { from, Subject } from 'rxjs';
import {
  getClimateEntityUpdates,
  getHeatingApiUpdates,
  getTrvApiUpdates,
  setClimateEntityMode,
  setClimateEntityTemperature,
} from './home-assistant';
import {
  HomeAssistantApi,
  HomeAssistantApiLive,
  HomeAssistantConfig,
  HomeAssistantConfigLive,
} from './home-assistant-api';
import { Effect, Layer, pipe, Option, Runtime } from 'effect';
import { Schema } from '@effect/schema';
import { EntityId, HassState } from './schema';

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
export const createHomeAssistantProvider: () => HeatingProvider = () => {
  const runtime = pipe(
    HomeAssistantApiLive.pipe(Layer.merge(HomeAssistantConfigLive)),
    Layer.toRuntime,
    Effect.scoped,
    Effect.runSync
  );

  const heatingActions = new Subject<HeatingAction>();
  const trvActions = new Subject<TrvAction>();

  const setClimateEntity =
    (runtime: Runtime.Runtime<HomeAssistantApi | HomeAssistantConfig>) =>
    (
      entityId: EntityId,
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
              Schema.decodeSync(EntityId)(action.heatingId),
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
              Schema.decodeSync(EntityId)(action.trvId),
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

  const climateEntityUpdates$ = getClimateEntityUpdates(runtime);

  return {
    trvActions,
    heatingActions,
    trvApiUpdates$: getTrvApiUpdates(climateEntityUpdates$),
    heatingApiUpdates$: getHeatingApiUpdates(climateEntityUpdates$),
  };
};
