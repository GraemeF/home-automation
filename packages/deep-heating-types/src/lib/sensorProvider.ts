import { Observable } from 'rxjs';
import { SensorUpdate } from './deep-heating-types';

export type SensorProvider = {
  sensorUpdates$: Observable<SensorUpdate>;
};
