import { Schema } from '@effect/schema';
import {
  ButtonPressEventEntity,
  Home,
  HomeAssistantEntity,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { filter } from 'rxjs/operators';

export const createHomeAssistantButtonEventProvider: (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>
) => { buttonPressEvents$: Observable<ButtonPressEventEntity> } = (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>
) => ({
  buttonPressEvents$: entityUpdates$.pipe(
    filter(Schema.is(ButtonPressEventEntity)),
    filter((entity) => entity.entity_id === home.sleepSwitchId),
    shareReplayLatestDistinctByKey(
      (x) => x.entity_id,
      (a, b) => a.state === b.state
    )
  ),
});
