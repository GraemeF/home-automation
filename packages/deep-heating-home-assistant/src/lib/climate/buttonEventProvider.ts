import { Schema } from '@effect/schema';
import { ButtonEvent } from '@home-automation/deep-heating-types';
import { DateTime } from 'luxon';
import { Observable } from 'rxjs';
import { filter, map } from 'rxjs/operators';
import { ButtonPressEventEntity, HomeAssistantEntity } from '../entity';

export const createHomeAssistantButtonEventProvider: (
  entityUpdates$: Observable<HomeAssistantEntity>
) => { buttonPressEvents$: Observable<ButtonEvent> } = (
  entityUpdates$: Observable<HomeAssistantEntity>
) => ({
  buttonPressEvents$: entityUpdates$.pipe(
    filter(Schema.is(ButtonPressEventEntity)),
    map((entity: ButtonPressEventEntity) => ({
      switchId: entity.entity_id as string,
      switchName: entity.attributes.friendly_name,
      buttonIndex: 0,
      eventType: entity.attributes.event_type,
      time: DateTime.fromJSDate(entity.state),
    }))
  ),
});
