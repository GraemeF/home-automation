import { Effect, pipe } from 'effect';
import { HomeAssistantApiTest } from '../home-assistant-api';
import { ClimateEntity } from './climateEntity';
import { getClimateEntities } from './climate';

const exampleStates = [
  {
    entity_id: 'sensor.sun_next_dawn',
    state: '2023-10-01T05:30:22+00:00',
    attributes: {
      device_class: 'timestamp',
      icon: 'mdi:sun-clock',
      friendly_name: 'Sun Next dawn',
    },
    last_changed: '2023-09-30T15:49:07.488183+00:00',
    last_updated: '2023-09-30T15:49:07.488183+00:00',
    context: {
      id: 'some-id',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'event.lounge_switch_button_3',
    state: 'unknown',
    attributes: {
      event_types: [
        'initial_press',
        'repeat',
        'short_release',
        'long_press',
        'long_release',
      ],
      event_type: null,
      device_class: 'button',
      friendly_name: 'Lounge Switch Button 3',
    },
    last_changed: '2023-09-30T15:49:08.197062+00:00',
    last_updated: '2023-09-30T15:49:08.197062+00:00',
    context: {
      id: 'another-id',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'light.kitchen_hob_right',
    state: 'off',
    attributes: {
      min_color_temp_kelvin: 2000,
      max_color_temp_kelvin: 6535,
      min_mireds: 153,
      max_mireds: 500,
      effect_list: ['None', 'candle', 'fire', 'unknown'],
      supported_color_modes: ['color_temp', 'xy'],
      mode: 'normal',
      dynamics: 'none',
      friendly_name: 'Kitchen hob right',
      supported_features: 44,
    },
    last_changed: '2023-09-30T18:28:55.264217+00:00',
    last_updated: '2023-09-30T18:28:55.264217+00:00',
    context: {
      id: 'id-3',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'climate.kitchen',
    state: 'off',
    attributes: {
      hvac_modes: ['auto', 'heat', 'off'],
      min_temp: 5,
      max_temp: 32,
      preset_modes: ['boost', 'none'],
      current_temperature: 20.5,
      temperature: 7.0,
      hvac_action: 'idle',
      preset_mode: 'none',
      friendly_name: 'Kitchen',
      supported_features: 17,
    },
    last_changed: '2023-09-30T15:49:08.636456+00:00',
    last_updated: '2023-09-30T16:09:23.756730+00:00',
    context: {
      id: 'id-2',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'climate.panel_heater',
    state: 'off',
    attributes: {
      hvac_modes: ['off', 'heat'],
      min_temp: 5.0,
      max_temp: 40.0,
      target_temp_step: 1.0,
      current_temperature: 19.0,
      temperature: 8.0,
      friendly_name: 'Panel heater',
      supported_features: 1,
    },
    last_changed: '2023-09-30T15:49:08.480609+00:00',
    last_updated: '2023-09-30T15:49:08.480609+00:00',
    context: {
      id: 'id-4',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'climate.main',
    state: 'off',
    attributes: {
      hvac_modes: ['auto', 'heat', 'off'],
      min_temp: 5,
      max_temp: 32,
      preset_modes: ['boost', 'none'],
      current_temperature: 20.5,
      temperature: 7.0,
      hvac_action: 'idle',
      preset_mode: 'none',
      friendly_name: 'Heating thermostat',
      supported_features: 17,
    },
    last_changed: '2023-09-30T15:49:08.637521+00:00',
    last_updated: '2023-09-30T16:40:53.947834+00:00',
    context: {
      id: 'id-5',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'sensor.office_sensor_temperature',
    state: '21.2',
    attributes: {
      state_class: 'measurement',
      temperature_valid: true,
      unit_of_measurement: '°C',
      device_class: 'temperature',
      friendly_name: 'Office Sensor Temperature',
    },
    last_changed: '2023-09-30T18:27:38.204853+00:00',
    last_updated: '2023-09-30T18:27:38.204853+00:00',
    context: {
      id: 'id-6',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'sensor.garden_temperature',
    state: '16.0',
    attributes: {
      state_class: 'measurement',
      min_entity_id: 'sensor.pagoda_sensor_temperature',
      unit_of_measurement: '°C',
      icon: 'mdi:thermometer',
      friendly_name: 'Garden temperature',
    },
    last_changed: '2023-09-30T18:39:27.328391+00:00',
    last_updated: '2023-09-30T18:39:27.328391+00:00',
    context: {
      id: 'id-7',
      parent_id: null,
      user_id: null,
    },
  },
];

describe('home-assistant-api', () => {
  describe('getClimateEntities', () => {
    let result: readonly ClimateEntity[];

    beforeAll(async () => {
      result = await pipe(
        getClimateEntities,
        Effect.provide(HomeAssistantApiTest(Effect.succeed(exampleStates))),
        Effect.runPromise
      );
    });

    it('returns only the climate entities', async () => {
      expect(result).toHaveLength(3);
      expect(result.map((e) => e.entity_id)).toEqual([
        'climate.kitchen',
        'climate.panel_heater',
        'climate.main',
      ]);
    });
  });
});
