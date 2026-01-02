import { Context, Effect, Layer, pipe, Stream } from 'effect';
import { share } from 'rxjs';
import {
  ClimateEntityId,
  Home,
  HeatingSystem,
  HeatingSystemError,
  OperationalClimateMode,
  Temperature,
} from '@home-automation/deep-heating-types';
import { streamToObservable } from '@home-automation/rxx';
import {
  HomeAssistantConnectionError,
  SetHvacModeError,
  SetTemperatureError,
} from '../errors';
import {
  getEntityUpdatesStream,
  HomeAssistantApi,
} from '../home-assistant-api';
import {
  getClimateEntityUpdates,
  getHeatingApiUpdates,
  getTrvApiUpdates,
} from './climate';
import { createHomeAssistantSensorProvider } from './homeAssistantSensorProvider';
import { createHomeAssistantButtonEventProvider } from './buttonEventProvider';

// Extract error mapping to named function for lint compliance
const mapToHeatingSystemError = (
  e: Readonly<SetTemperatureError | SetHvacModeError>,
) => new HeatingSystemError({ message: e.message, cause: e });

// Create setTrvTemperature effect with proper error mapping
const createSetTrvTemperature =
  (api: Context.Tag.Service<typeof HomeAssistantApi>) =>
  (entityId: ClimateEntityId, temperature: Temperature) =>
    pipe(
      api.setTemperature(entityId, temperature),
      Effect.mapError(mapToHeatingSystemError),
      Effect.asVoid,
    );

// Create setTrvMode effect with proper error mapping
const createSetTrvMode =
  (api: Context.Tag.Service<typeof HomeAssistantApi>) =>
  (entityId: ClimateEntityId, mode: OperationalClimateMode) =>
    pipe(
      api.setHvacMode(entityId, mode),
      Effect.mapError(mapToHeatingSystemError),
      Effect.asVoid,
    );

// Release function for subscription cleanup
const releaseSubscription = ({
  subscription,
}: {
  readonly subscription: { readonly unsubscribe: () => void };
}) => {
  subscription.unsubscribe();
};

/**
 * Creates a Layer that provides HeatingSystem using Home Assistant as the backend.
 *
 * The layer manages the lifecycle of the entity polling stream and provides
 * all heating system observables and action methods.
 *
 * @param home - Home configuration with room and device mappings
 * @returns Layer providing HeatingSystem, requiring HomeAssistantApi
 */
export const HomeAssistantHeatingSystemLive = (
  home: Home,
): Layer.Layer<HeatingSystem, HomeAssistantConnectionError, HomeAssistantApi> =>
  Layer.scoped(
    HeatingSystem,
    pipe(
      HomeAssistantApi,
      Effect.flatMap((api) =>
        Effect.acquireRelease(
          // Acquire: set up the entity stream and observables
          Effect.sync(() => {
            // Create entity stream with API provided
            const entityStream = getEntityUpdatesStream.pipe(
              Stream.provideService(HomeAssistantApi, api),
            );

            // Convert to shared Observable (single polling stream for all consumers)
            const entityUpdates$ =
              streamToObservable(entityStream).pipe(share());

            // Keep-alive subscription to start polling
            const subscription = entityUpdates$.subscribe();

            // Build observables from shared stream
            const climateUpdates$ = getClimateEntityUpdates(entityUpdates$);
            const trvUpdates = climateUpdates$.pipe(getTrvApiUpdates(home));
            const heatingUpdates = getHeatingApiUpdates(climateUpdates$);
            const { sensorUpdates$ } =
              createHomeAssistantSensorProvider(entityUpdates$);
            const { buttonPressEvents$ } =
              createHomeAssistantButtonEventProvider(home, entityUpdates$);

            return {
              subscription,
              service: {
                trvUpdates,
                heatingUpdates,
                temperatureReadings: sensorUpdates$,
                sleepModeEvents: buttonPressEvents$,
                setTrvTemperature: createSetTrvTemperature(api),
                setTrvMode: createSetTrvMode(api),
              },
            };
          }),
          // Release: clean up subscription
          (resources) =>
            Effect.sync(() => {
              releaseSubscription(resources);
            }),
        ),
      ),
      Effect.map(({ service }) => service),
    ),
  );
