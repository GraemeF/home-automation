import { Schema } from '@effect/schema';
import {
  ButtonEvent,
  ButtonPressEventEntity,
  EventEntityId,
  Home,
  HomeAssistantEntity,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestByKey } from '@home-automation/rxx';
import { DateTime } from 'luxon';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';

export const createHomeAssistantButtonEventProvider: (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>
) => { buttonPressEvents$: Observable<ButtonEvent> } = (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>
) => ({
  buttonPressEvents$: entityUpdates$.pipe(
    filter(Schema.is(ButtonPressEventEntity)),
    filter(
      (entity) =>
        entity.entity_id === Schema.parseSync(EventEntityId)(home.sleepSwitchId)
    ),
    map((entity: ButtonPressEventEntity) => ({
      switchId: entity.entity_id as string,
      switchName: entity.attributes.friendly_name,
      buttonIndex: 0,
      eventType: entity.attributes.event_type,
      time: DateTime.fromJSDate(entity.state),
    })),
    shareReplayLatestByKey((x) => x.switchId)
  ),
});
