import { describe, expect, it, layer } from '@codeforbreakfast/bun-test-effect';
import { Effect, Ref, Schema } from 'effect';
import { firstValueFrom, Subject, take, toArray } from 'rxjs';
import { ClimateEntityId } from './entities';
import {
  OperationalClimateMode,
  TemperatureSensorEntity,
} from './home-assistant';
import { HeatingSystem } from './heatingSystem';
import {
  type HeatingSystemAction,
  InMemoryHeatingSystemLive,
  makeInMemoryHeatingSystem,
} from './inMemoryHeatingSystem';
import { Temperature } from './temperature';
import { TrvUpdate } from './deep-heating-types';

// Decoder functions for creating properly typed test data
const decodeClimateEntityId = Schema.decodeSync(ClimateEntityId);
const decodeTemperature = Schema.decodeSync(Temperature);
const decodeMode = Schema.decodeSync(OperationalClimateMode);

// Helper: create actions Ref and heating system, then run test effect
const withFreshHeatingSystem = <A, E>(
  testFn: (ctx: {
    readonly heatingSystem: ReturnType<
      typeof makeInMemoryHeatingSystem
    >['heatingSystem'];
    readonly getRecordedActions: ReturnType<
      typeof makeInMemoryHeatingSystem
    >['getRecordedActions'];
  }) => Effect.Effect<A, E>,
): Effect.Effect<A, E> =>
  Effect.flatMap(Ref.make<readonly HeatingSystemAction[]>([]), (actionsRef) =>
    testFn(makeInMemoryHeatingSystem(actionsRef)),
  );

// Helper: create heating system with custom subjects
const withHeatingSystemSubjects = <A, E>(
  subjects: Parameters<typeof makeInMemoryHeatingSystem>[1],
  testFn: (ctx: {
    readonly heatingSystem: ReturnType<
      typeof makeInMemoryHeatingSystem
    >['heatingSystem'];
    readonly getRecordedActions: ReturnType<
      typeof makeInMemoryHeatingSystem
    >['getRecordedActions'];
  }) => Effect.Effect<A, E>,
): Effect.Effect<A, E> =>
  Effect.flatMap(Ref.make<readonly HeatingSystemAction[]>([]), (actionsRef) =>
    testFn(makeInMemoryHeatingSystem(actionsRef, subjects)),
  );

describe('InMemoryHeatingSystem', () => {
  describe('makeInMemoryHeatingSystem', () => {
    it.effect('creates a HeatingSystem with empty action log', () =>
      withFreshHeatingSystem(({ heatingSystem, getRecordedActions }) => {
        // Should have all the required observables
        expect(heatingSystem.trvUpdates).toBeDefined();
        expect(heatingSystem.heatingUpdates).toBeDefined();
        expect(heatingSystem.temperatureReadings).toBeDefined();
        expect(heatingSystem.sleepModeEvents).toBeDefined();

        // Should have action methods
        expect(heatingSystem.setTrvTemperature).toBeDefined();
        expect(heatingSystem.setTrvMode).toBeDefined();

        // Actions should be empty initially
        return Effect.map(getRecordedActions, (actions) => {
          expect(actions).toEqual([]);
        });
      }),
    );
  });

  describe('setTrvTemperature', () => {
    it.effect('records temperature action in the action log', () =>
      withFreshHeatingSystem(({ heatingSystem, getRecordedActions }) =>
        Effect.andThen(
          heatingSystem.setTrvTemperature(
            decodeClimateEntityId('climate.living_room'),
            decodeTemperature(21),
          ),
          Effect.map(getRecordedActions, (actions) => {
            expect(actions).toEqual([
              {
                type: 'setTemperature',
                entityId: 'climate.living_room',
                temperature: 21,
              },
            ]);
          }),
        ),
      ),
    );

    it.effect('records multiple temperature actions in order', () =>
      withFreshHeatingSystem(({ heatingSystem, getRecordedActions }) =>
        Effect.all([
          heatingSystem.setTrvTemperature(
            decodeClimateEntityId('climate.living_room'),
            decodeTemperature(21),
          ),
          heatingSystem.setTrvTemperature(
            decodeClimateEntityId('climate.bedroom'),
            decodeTemperature(18),
          ),
        ]).pipe(
          Effect.andThen(
            Effect.map(getRecordedActions, (actions) => {
              expect(actions).toEqual([
                {
                  type: 'setTemperature',
                  entityId: 'climate.living_room',
                  temperature: 21,
                },
                {
                  type: 'setTemperature',
                  entityId: 'climate.bedroom',
                  temperature: 18,
                },
              ]);
            }),
          ),
        ),
      ),
    );
  });

  describe('setTrvMode', () => {
    it.effect('records mode action in the action log', () =>
      withFreshHeatingSystem(({ heatingSystem, getRecordedActions }) =>
        Effect.andThen(
          heatingSystem.setTrvMode(
            decodeClimateEntityId('climate.living_room'),
            decodeMode('heat'),
          ),
          Effect.map(getRecordedActions, (actions) => {
            expect(actions).toEqual([
              {
                type: 'setMode',
                entityId: 'climate.living_room',
                mode: 'heat',
              },
            ]);
          }),
        ),
      ),
    );
  });

  describe('mixed actions', () => {
    it.effect('records temperature and mode actions in order', () =>
      withFreshHeatingSystem(({ heatingSystem, getRecordedActions }) =>
        Effect.all([
          heatingSystem.setTrvTemperature(
            decodeClimateEntityId('climate.living_room'),
            decodeTemperature(21),
          ),
          heatingSystem.setTrvMode(
            decodeClimateEntityId('climate.living_room'),
            decodeMode('auto'),
          ),
          heatingSystem.setTrvTemperature(
            decodeClimateEntityId('climate.bedroom'),
            decodeTemperature(18),
          ),
        ]).pipe(
          Effect.andThen(
            Effect.map(getRecordedActions, (actions) => {
              expect(actions).toEqual([
                {
                  type: 'setTemperature',
                  entityId: 'climate.living_room',
                  temperature: 21,
                },
                {
                  type: 'setMode',
                  entityId: 'climate.living_room',
                  mode: 'auto',
                },
                {
                  type: 'setTemperature',
                  entityId: 'climate.bedroom',
                  temperature: 18,
                },
              ]);
            }),
          ),
        ),
      ),
    );
  });

  describe('observables emit pushed values', () => {
    it.effect('emits TRV updates when pushed to subject', () => {
      const trvSubject = new Subject<TrvUpdate>();
      return withHeatingSystemSubjects(
        { trvUpdates: trvSubject },
        ({ heatingSystem }) => {
          const updates = heatingSystem.trvUpdates.pipe(take(1), toArray());
          const updatePromise = firstValueFrom(updates);

          trvSubject.next({
            climateEntityId: decodeClimateEntityId('climate.living_room'),
            name: 'Living Room',
            deviceType: 'trv',
            state: {
              temperature: decodeTemperature(19),
              target: decodeTemperature(21),
              mode: decodeMode('heat'),
              isHeating: true,
              schedule: {},
            },
          });

          return Effect.map(
            Effect.promise(() => updatePromise),
            (received) => {
              expect(received).toHaveLength(1);
              expect(received[0]?.climateEntityId).toBe('climate.living_room');
            },
          );
        },
      );
    });

    it.effect('emits temperature readings when pushed to subject', () => {
      const tempSubject = new Subject<TemperatureSensorEntity>();
      return withHeatingSystemSubjects(
        { temperatureReadings: tempSubject },
        ({ heatingSystem }) => {
          const readings = heatingSystem.temperatureReadings.pipe(
            take(1),
            toArray(),
          );
          const readingsPromise = firstValueFrom(readings);

          tempSubject.next({
            entity_id: 'sensor.living_room_temp',
            state: decodeTemperature(19.5),
            attributes: {
              device_class: 'temperature',
              friendly_name: 'Living Room Temperature',
            },
          });

          return Effect.map(
            Effect.promise(() => readingsPromise),
            (received) => {
              expect(received).toHaveLength(1);
              expect(received[0]?.entity_id).toBe('sensor.living_room_temp');
            },
          );
        },
      );
    });
  });

  describe('InMemoryHeatingSystemLive Layer', () => {
    const withInMemoryHeatingSystem = layer(InMemoryHeatingSystemLive);

    withInMemoryHeatingSystem(
      'provides HeatingSystem service',
      ({ effect }) => {
        effect('exposes all required observables via Effect Layer', () =>
          Effect.map(HeatingSystem, (heatingSystem) => {
            expect(heatingSystem.trvUpdates).toBeDefined();
            expect(heatingSystem.heatingUpdates).toBeDefined();
            expect(heatingSystem.temperatureReadings).toBeDefined();
            expect(heatingSystem.sleepModeEvents).toBeDefined();
          }),
        );
      },
    );
  });
});
