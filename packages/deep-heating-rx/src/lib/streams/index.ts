import { Subject, timer } from 'rxjs';
import { DeepHeating } from './DeepHeating';
import { RoomAdjustment } from '@home-automation/deep-heating-types';

const deepHeating = new DeepHeating(new Subject<RoomAdjustment>());

deepHeating.roomTemperatures$.subscribe((x) =>
  console.log(
    x.roomName,
    'was',
    x.temperatureReading.temperature,
    x.temperatureReading.time.toRelative()
  )
);

deepHeating.roomTargetTemperatures$.subscribe((x) =>
  console.log(x.roomName, 'should be', x.targetTemperature)
);

deepHeating.trvTemperatures$.subscribe((x) =>
  console.log('TRV', x.trvId, 'is reporting', x.temperatureReading)
);

deepHeating.trvActions$.subscribe((x) =>
  console.log('TRV', x.trvId, 'should change to', x.mode, x.targetTemperature)
);

deepHeating.trvControlStates$.subscribe((x) =>
  console.log('TRV', x.trvId, 'is set to', x.mode, x.targetTemperature)
);

deepHeating.appliedHeatingActions$.subscribe((x) =>
  console.log(
    'Heating',
    x.heatingId,
    'has been changed to',
    x.isHeating ? 'heating' : 'cooling'
  )
);

deepHeating.heatingActions$.subscribe((x) =>
  console.log(
    'Heating',
    x.heatingId,
    'should change to',
    x.mode,
    x.targetTemperature
  )
);

deepHeating.trvStatuses$.subscribe((x) =>
  console.log('TRV', x.trvId, x.isHeating ? 'is heating' : 'is cooling')
);

deepHeating.heatingStatuses$.subscribe((x) =>
  console.log('Heating', x.heatingId, x.isHeating ? 'is heating' : 'is cooling')
);

timer(0, 10000).subscribe(() => console.log());
