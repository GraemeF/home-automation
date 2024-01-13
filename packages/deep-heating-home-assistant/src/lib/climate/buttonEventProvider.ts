import {
  GoodnightEventEntity,
  Home,
  HomeAssistantEntity,
  InputButtonEntity,
  isSchema,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { Observable } from 'rxjs';
import { filter } from 'rxjs/operators';

export const createHomeAssistantButtonEventProvider: (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>,
) => { buttonPressEvents$: Observable<GoodnightEventEntity> } = (
  home: Home,
  entityUpdates$: Observable<HomeAssistantEntity>,
) => ({
  buttonPressEvents$: entityUpdates$.pipe(
    filter(isSchema(InputButtonEntity)),
    filter((entity) => entity.entity_id === home.sleepSwitchId),
    shareReplayLatestDistinctByKey(
      (x) => x.entity_id,
      (a, b) => a.state.getTime() === b.state.getTime(),
    ),
  ),
});
