import { Effect, pipe } from 'effect';
import {
  HomeAssistantConfigLive,
  getClimateEntities,
} from './home-assistant-api';

describe('home-assistant-api', () => {
  it('queries stuff', async () =>
    expect(
      await pipe(
        getClimateEntities,
        Effect.provide(HomeAssistantConfigLive),
        Effect.runPromise
      )
    ).toHaveLength(8));
});
