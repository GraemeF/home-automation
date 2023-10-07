import {
  HeatingAction,
  HeatingProvider,
  TrvAction,
  TrvModeValue,
} from '@home-automation/deep-heating-types';
import debug from 'debug';
import { debounceTime, groupBy, mergeMap } from 'rxjs/operators';
import { from, Subject } from 'rxjs';
import {
  getClimateEntityUpdates,
  getHeatingApiUpdates,
  getTrvApiUpdates,
  setClimateEntityState,
} from './home-assistant';
import {
  HomeAssistantApiLive,
  HomeAssistantConfigLive,
} from './home-assistant-api';
import { Effect, Layer, pipe } from 'effect';
import { Schema } from '@effect/schema';
import { EntityId, HassState, Temperature } from './schema';

const log = debug('home-assistant');

const trvModeValueToHassState: (mode: TrvModeValue) => HassState = (mode) => {
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

  const setClimate = setClimateEntityState(runtime);

  heatingActions
    .pipe(
      debounceTime(5000),
      mergeMap((action) =>
        from(
          setClimate(
            Schema.decodeSync(EntityId)(action.heatingId),
            trvModeValueToHassState(action.mode),
            Schema.decodeSync(Temperature)(action.targetTemperature)
          )
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
        from(
          setClimate(
            Schema.decodeSync(EntityId)(action.trvId),
            trvModeValueToHassState(action.mode),
            Schema.decodeSync(Temperature)(action.targetTemperature)
          )
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
