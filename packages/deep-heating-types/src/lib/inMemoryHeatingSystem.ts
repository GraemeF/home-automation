import { Context, Effect, Layer, pipe, Ref } from 'effect';
import { EMPTY, type Observable, Subject } from 'rxjs';
import type { HeatingUpdate, TrvUpdate } from './deep-heating-types';
import type { ClimateEntityId } from './entities';
import type {
  GoodnightEventEntity,
  OperationalClimateMode,
  TemperatureSensorEntity,
} from './home-assistant';
import { HeatingSystem } from './heatingSystem';
import type { Temperature } from './temperature';

/**
 * Action types for recording HeatingSystem operations.
 */
export interface SetTemperatureAction {
  readonly type: 'setTemperature';
  readonly entityId: ClimateEntityId;
  readonly temperature: Temperature;
}

export interface SetModeAction {
  readonly type: 'setMode';
  readonly entityId: ClimateEntityId;
  readonly mode: OperationalClimateMode;
}

export type HeatingSystemAction = SetTemperatureAction | SetModeAction;

/**
 * Optional subjects to override default empty observables.
 */
export interface InMemoryHeatingSystemSubjects {
  readonly trvUpdates?: Subject<TrvUpdate>;
  readonly heatingUpdates?: Subject<HeatingUpdate>;
  readonly temperatureReadings?: Subject<TemperatureSensorEntity>;
  readonly sleepModeEvents?: Subject<GoodnightEventEntity>;
}

/**
 * Result of makeInMemoryHeatingSystem containing the service and action retrieval.
 */
export interface InMemoryHeatingSystemResult {
  readonly heatingSystem: Context.Tag.Service<typeof HeatingSystem>;
  readonly getRecordedActions: Effect.Effect<readonly HeatingSystemAction[]>;
}

/**
 * Creates an in-memory HeatingSystem implementation for testing.
 *
 * Uses a Ref to store actions functionally without mutable state.
 * Actions can be retrieved via the returned getRecordedActions Effect.
 *
 * @param actionsRef - Ref to store recorded actions
 * @param subjects - Optional subjects to provide test data via observables
 * @returns HeatingSystem implementation and Effect to retrieve recorded actions
 */
export const makeInMemoryHeatingSystem = (
  actionsRef: Ref.Ref<readonly HeatingSystemAction[]>,
  subjects: InMemoryHeatingSystemSubjects = {},
): InMemoryHeatingSystemResult => {
  const heatingSystem: Context.Tag.Service<typeof HeatingSystem> = {
    trvUpdates: (subjects.trvUpdates ?? EMPTY) as Observable<TrvUpdate>,
    heatingUpdates: (subjects.heatingUpdates ??
      EMPTY) as Observable<HeatingUpdate>,
    temperatureReadings: (subjects.temperatureReadings ??
      EMPTY) as Observable<TemperatureSensorEntity>,
    sleepModeEvents: (subjects.sleepModeEvents ??
      EMPTY) as Observable<GoodnightEventEntity>,

    setTrvTemperature: (entityId: ClimateEntityId, temperature: Temperature) =>
      pipe(
        actionsRef,
        Ref.update((actions) => [
          ...actions,
          { type: 'setTemperature' as const, entityId, temperature },
        ]),
      ),

    setTrvMode: (entityId: ClimateEntityId, mode: OperationalClimateMode) =>
      pipe(
        actionsRef,
        Ref.update((actions) => [
          ...actions,
          { type: 'setMode' as const, entityId, mode },
        ]),
      ),
  };

  return { heatingSystem, getRecordedActions: Ref.get(actionsRef) };
};

/**
 * Effect Layer providing InMemoryHeatingSystem as the HeatingSystem service.
 *
 * Uses empty observables by default. For tests that need to emit values,
 * use makeInMemoryHeatingSystem directly with custom subjects.
 */
export const InMemoryHeatingSystemLive: Layer.Layer<HeatingSystem> =
  Layer.effect(
    HeatingSystem,
    Effect.map(
      Ref.make<readonly HeatingSystemAction[]>([]),
      (actionsRef) => makeInMemoryHeatingSystem(actionsRef).heatingSystem,
    ),
  );
