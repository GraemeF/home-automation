import * as Schema from '@effect/schema/Schema';
import {
  ButtonPressEventEntity,
  ClimateEntity,
  HomeAssistantEntity,
  InputButtonEntity,
  OtherEntity,
  SensorEntity,
  TemperatureSensorEntity,
} from '@home-automation/deep-heating-types';
import { Effect, pipe } from 'effect';
import { HomeAssistantApiTest, getEntities } from './home-assistant-api';

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
    entity_id: 'event.hall_button_button_1',
    state: '2023-10-07T22:24:18.321+00:00',
    attributes: {
      event_types: [
        'initial_press',
        'repeat',
        'short_release',
        'long_press',
        'long_release',
      ],
      event_type: 'short_release',
      device_class: 'button',
      friendly_name: 'Hall Button Button 1',
    },
    last_changed: '2023-10-07T22:24:18.322157+00:00',
    last_updated: '2023-10-07T22:24:18.322157+00:00',
    context: {
      id: '01HC63VJWJQBDPBGT1GSY0DDZS',
      parent_id: null,
      user_id: null,
    },
  },
  {
    entity_id: 'input_button.goodnight',
    state: '2023-11-06T15:55:43.780707+00:00',
    attributes: {
      editable: true,
      icon: 'mdi:sleep',
      friendly_name: 'Goodnight',
    },
    last_changed: '2023-11-06T15:55:43.781002+00:00',
    last_updated: '2023-11-06T15:55:43.781002+00:00',
    context: {
      id: '01HEJNHMRZJF9R8V0M6FE9CKJ8',
      parent_id: null,
      user_id: 'fc1789cda34e4ca1927b07140b90a16f',
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
  describe('getEntities', () => {
    let entities: ReadonlyArray<HomeAssistantEntity>;
    beforeAll(async () => {
      entities = await pipe(
        getEntities,
        Effect.provide(HomeAssistantApiTest(Effect.succeed(exampleStates))),
        Effect.runPromise
      );
    });
    it('parses all entities', async () => {
      expect(entities).toHaveLength(10);
    });

    it('parses climate entities', async () => {
      expect(
        entities.filter(Schema.is(ClimateEntity)).map((e) => e.entity_id)
      ).toHaveLength(3);
    });

    it('parses sensor entities', async () => {
      expect(
        entities.filter(Schema.is(SensorEntity)).map((e) => e.entity_id)
      ).toHaveLength(3);
    });

    it('parses temperature sensor entities', async () => {
      expect(
        entities
          .filter(Schema.is(TemperatureSensorEntity))
          .map((e) => e.entity_id)
      ).toHaveLength(2);
    });

    it('parses button press event entities', async () => {
      expect(
        entities
          .filter(Schema.is(ButtonPressEventEntity))
          .map((e) => e.entity_id)
      ).toHaveLength(1);
    });

    it('parses input button entities', async () => {
      expect(
        entities.filter(Schema.is(InputButtonEntity)).map((e) => e.entity_id)
      ).toHaveLength(1);
    });

    it('parses other entities', async () => {
      expect(
        entities.filter(Schema.is(OtherEntity)).map((e) => e.entity_id)
      ).toHaveLength(6);
    });
  });
});
