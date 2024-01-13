import {
  HomeAssistantEntity,
  TemperatureSensorEntity,
  isSchema,
} from '@home-automation/deep-heating-types';
import { Observable } from 'rxjs';
import { filter } from 'rxjs/operators';

export const createHomeAssistantSensorProvider: (
  entityUpdates$: Observable<HomeAssistantEntity>,
) => { sensorUpdates$: Observable<TemperatureSensorEntity> } = (
  entityUpdates$: Observable<HomeAssistantEntity>,
) => ({
  sensorUpdates$: entityUpdates$.pipe(
    filter(isSchema(TemperatureSensorEntity)),
  ),
});
