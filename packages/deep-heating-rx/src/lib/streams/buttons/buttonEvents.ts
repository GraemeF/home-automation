import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import {
  ButtonEvent,
  SwitchSensorUpdate,
} from '@home-automation/deep-heating-types';
import { parseHueTime } from '@home-automation/deep-heating-hue';

export function getButtonEvents(
  switchSensorStates$: Observable<SwitchSensorUpdate>
): Observable<ButtonEvent> {
  return switchSensorStates$.pipe(
    filter((x: SwitchSensorUpdate) => x.state.buttonevent !== null),
    map(toButtonEvent)
  );
}

function toButtonEvent(t: SwitchSensorUpdate): ButtonEvent {
  const button = t.capabilities.inputs.find(
    (x) => x.events.findIndex((y) => y.buttonevent === t.state.buttonevent) > -1
  );
  const buttonNumber = t.capabilities.inputs.indexOf(button);
  return {
    switchId: t.uniqueid,
    switchName: t.name,
    buttonIndex: buttonNumber,
    eventType: button.events.find((y) => y.buttonevent === t.state.buttonevent)
      .eventtype,
    time: parseHueTime(t.state.lastupdated),
  };
}
