import { derived, writable, get } from 'svelte/store';
import type { Readable } from 'svelte/store';
import { apiClientStore } from './apiClient';
import type { Socket } from 'socket.io-client';
import type { DefaultEventsMap } from 'socket.io/dist/typed-events';
import type { DeepHeatingState } from '@home-automation/deep-heating-types';

interface Home {
  connected: boolean;
  state: DeepHeatingState | null;
}

export const homeStore = derived<
  Readable<Socket<DefaultEventsMap, DefaultEventsMap>>,
  Home
>(
  apiClientStore,
  ($apiClient, set) => {
    const home = writable<Home>({
      connected: false,
      state: null,
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
          home.update((home) => ({ ...home, state }));
          set(get(home));
        });
  },
  { connected: false, state: null }
);
