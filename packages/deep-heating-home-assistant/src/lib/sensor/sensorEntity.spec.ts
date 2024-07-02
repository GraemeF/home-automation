import { Schema } from '@effect/schema';
import { TemperatureSensorEntity } from '@home-automation/deep-heating-types';
import { Effect } from 'effect';
import { pipe } from 'effect/Function';

const exampleSensorEntity = {
  entity_id: 'sensor.bedroom_sensor_temperature',
  state: '21.1',
  attributes: {
    state_class: 'measurement',
    unit_of_measurement: '°C',
    device_class: 'temperature',
    friendly_name: 'Bedroom Sensor Temperature',
  },
  last_changed: '2023-10-08T08:01:09.725124+00:00',
  last_updated: '2023-10-08T08:01:09.725124+00:00',
  context: {
    id: 'some_id',
    parent_id: null,
    user_id: null,
  },
};

describe('sensor', () => {
  describe('schema', () => {
    it('decodes a sensor entity', () => {
      expect(
        pipe(
          exampleSensorEntity,
          Schema.decodeUnknown(TemperatureSensorEntity),
          Effect.runSync,
        ),
      ).toStrictEqual({
        entity_id: 'sensor.bedroom_sensor_temperature',
        state: 21.1,
        attributes: {
          device_class: 'temperature',
          friendly_name: 'Bedroom Sensor Temperature',
          state_class: 'measurement',
          unit_of_measurement: '°C',
        },
        last_changed: new Date('2023-10-08T08:01:09.725124Z'),
        last_updated: new Date('2023-10-08T08:01:09.725124Z'),
        context: {
          id: 'some_id',
          parent_id: null,
          user_id: null,
        },
      });
    });
  });
});
