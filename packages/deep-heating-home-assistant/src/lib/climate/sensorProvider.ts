import { Schema } from '@effect/schema';
import { SensorUpdate } from '@home-automation/deep-heating-types';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { HomeAssistantEntity, TemperatureSensorEntity } from '../entity';

export const createHomeAssistantSensorProvider: (
  entityUpdates$: Observable<HomeAssistantEntity>
) => { sensorUpdates$: Observable<SensorUpdate> } = (
  entityUpdates$: Observable<HomeAssistantEntity>
) => ({
  sensorUpdates$: entityUpdates$.pipe(
    filter(Schema.is(TemperatureSensorEntity)),
    map((entity) => ({
      uniqueid: entity.entity_id as string,
      state: {
        temperature: entity.state * 100,
        lastupdated: entity.last_updated.toISOString(),
      },
      type: 'ZLLTemperature',
    }))
  ),
});
