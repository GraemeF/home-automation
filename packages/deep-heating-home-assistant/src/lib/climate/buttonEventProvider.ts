import { Schema } from '@effect/schema';
import {
  ButtonPressEventEntity,
  EventEntityId,
  Home,
  HomeAssistantEntity,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestByKey } from '@home-automation/rxx';
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
    filter(
      (entity) =>
        entity.entity_id === Schema.parseSync(EventEntityId)(home.sleepSwitchId)
    ),
    shareReplayLatestByKey((x) => x.entity_id)
  ),
});
