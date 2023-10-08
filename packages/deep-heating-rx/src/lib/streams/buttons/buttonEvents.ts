import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import {
  ButtonEvent,
  SwitchSensorUpdate,
} from '@home-automation/deep-heating-types';
import { parseHueTime } from '@home-automation/deep-heating-hue';
import { isNotUndefined } from 'effect/Predicate';

export function getButtonEvents(
  switchSensorStates$: Observable<SwitchSensorUpdate>
): Observable<ButtonEvent> {
  return switchSensorStates$.pipe(
    filter((x: SwitchSensorUpdate) => x.state.buttonevent !== null),
    map(toButtonEvent),
    filter(isNotUndefined),
    filter((buttonEvent) => isNotUndefined(buttonEvent?.eventType))
  );
}

function toButtonEvent(t: SwitchSensorUpdate): ButtonEvent | undefined {
  const button = t.capabilities.inputs.find(
    (x) => x.events.findIndex((y) => y.buttonevent === t.state.buttonevent) > -1
  );
  if (button === undefined) {
    return undefined;
  }
  const buttonNumber = t.capabilities.inputs.indexOf(button);
  const eventType = button.events.find(
    (y) => y.buttonevent === t.state.buttonevent
  )?.eventtype;
  if (eventType === undefined) {
    return undefined;
  }
  return {
    switchId: t.uniqueid,
    switchName: t.name,
    buttonIndex: buttonNumber,
    eventType,
    time: parseHueTime(t.state.lastupdated),
  };
}
