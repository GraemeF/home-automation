import { Schema } from '@effect/schema';
import { ButtonEvent, Home } from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import {
  ButtonPressEventEntity,
  EventEntityId,
  HomeAssistantEntity,
} from '../entity';

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
    }))
  ),
});
