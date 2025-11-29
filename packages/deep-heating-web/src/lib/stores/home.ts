import { Schema } from 'effect';
import { DeepHeatingState } from '@home-automation/deep-heating-types';
import { Option } from 'effect';
import type { Socket } from 'socket.io-client';
import type { DefaultEventsMap } from 'socket.io/dist/typed-events';
import type { Readable } from 'svelte/store';
import { derived, get, writable } from 'svelte/store';
import { apiClientStore } from './apiClient';

interface Home {
  connected: boolean;
  state: Option.Option<DeepHeatingState>;
}

export const homeStore = derived<
  Readable<Socket<DefaultEventsMap, DefaultEventsMap> | null>,
  Home
>(
  apiClientStore,
  ($apiClient, set) => {
    const home = writable<Home>({
      connected: false,
      state: Option.none(),
    });

    if ($apiClient)
      $apiClient
        .on('connect', () => {
          home.update((home) => ({ ...home, connected: true }));
          set(get(home));
        })
        .on('disconnect', () => {
          home.update((home) => ({ ...home, connected: false }));
          set(get(home));
        })
        .on('State', (state) => {
          home.update((home) => ({
            ...home,
            state: Option.some(
              Schema.decodeUnknownSync(DeepHeatingState)(state),
            ),
          }));
          set(get(home));
        });
  },
  { connected: false, state: Option.none() },
);
