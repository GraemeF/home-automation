import { describe, expect, it } from 'bun:test';
import { Schema } from 'effect';
import { Effect } from 'effect';
import { pipe } from 'effect/Function';
import { ClimateEntity } from './entity';

const exampleClimateEntity = {
  entity_id: 'climate.bedroom_radiator',
  state: 'off',
  attributes: {
    hvac_modes: ['auto', 'heat', 'off'],
    min_temp: 5,
    max_temp: 32,
    preset_modes: ['boost', 'none'],
    current_temperature: 21.9,
    temperature: 7.0,
    hvac_action: 'idle',
    preset_mode: 'none',
    friendly_name: 'Bedroom Radiator',
    supported_features: 17,
  },
  last_changed: '2023-09-30T16:18:33.488856+00:00',
  last_updated: '2023-09-30T16:18:33.488856+00:00',
  context: {
    id: '01HBKE4VCG4JEPC98318WP444T',
    parent_id: null,
    user_id: null,
  },
};

describe('climate', () => {
  describe('schema', () => {
    it('decodes a climate entity', () => {
      expect(
        pipe(
          exampleClimateEntity,
          Schema.decodeUnknown(ClimateEntity),
          Effect.runSync,
        ),
      ).toStrictEqual({
        ...exampleClimateEntity,
        last_changed: new Date('2023-09-30T16:18:33.488Z'),
        last_updated: new Date('2023-09-30T16:18:33.488Z'),
      });
    });
  });
});
