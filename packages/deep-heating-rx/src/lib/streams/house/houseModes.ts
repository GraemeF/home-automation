import { Observable, timer } from 'rxjs';
import {
  filter,
  map,
  shareReplay,
  startWith,
  withLatestFrom,
} from 'rxjs/operators';
import { DateTime } from 'luxon';
import {
  ButtonEvent,
  HouseModeValue,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';

const refreshIntervalSeconds = 63;

export function getHouseMode(
  time: DateTime,
  lastButtonTime?: DateTime
): HouseModeValue {
  if (lastButtonTime) {
    if (lastButtonTime.startOf('day').equals(time.startOf('day'))) {
      if (lastButtonTime.hour > 20) return 'Sleeping';
    }
  }
  return time.hour < 5 ? 'Sleeping' : 'Auto';
}

export function getHouseModes(
  buttonEvents$: Observable<ButtonEvent>,
  sleepSwitchId: string
): Observable<HouseModeValue> {
  const time$ = timer(0, refreshIntervalSeconds * 1000).pipe(
    map(() => DateTime.local()),
    shareReplay(1)
  );

  return time$.pipe(
    withLatestFrom(
      buttonEvents$.pipe(
        filter((x) => x.switchId === sleepSwitchId),
        startWith(undefined)
      )
    ),
    map(([time, lastButtonEvent]) => getHouseMode(time, lastButtonEvent?.time)),
    shareReplayLatestDistinct()
  );
}
