import {
  GoodnightEntityId,
  GoodnightEventEntity,
  HouseModeValue,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';
import { DateTime } from 'luxon';
import { Observable, timer } from 'rxjs';
import {
  filter,
  map,
  shareReplay,
  startWith,
  withLatestFrom,
} from 'rxjs/operators';
import { localNow } from '../../utils/datetime';

const refreshIntervalSeconds = 63;

const getHouseMode = (
  now: DateTime,
  lastButtonTime?: DateTime,
): HouseModeValue =>
  lastButtonTime &&
  lastButtonTime.startOf('day').equals(now.startOf('day')) &&
  lastButtonTime.hour > 20
    ? 'Sleeping'
    : now.hour < 3
      ? 'Sleeping'
      : 'Auto';

export const getHouseModes = (
  buttonEvents$: Observable<GoodnightEventEntity>,
  sleepSwitchId: GoodnightEntityId,
): Observable<HouseModeValue> =>
  timer(0, refreshIntervalSeconds * 1000)
    .pipe(map(localNow), shareReplay(1))
    .pipe(
      withLatestFrom(
        buttonEvents$.pipe(
          filter((x) => x.entity_id === sleepSwitchId),
          startWith(undefined),
        ),
      ),
      map(([time, lastButtonEvent]) =>
        getHouseMode(
          time,
          lastButtonEvent
            ? DateTime.fromJSDate(lastButtonEvent.state)
            : undefined,
        ),
      ),
      shareReplayLatestDistinct(),
    );
