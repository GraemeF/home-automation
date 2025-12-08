import type { DeepHeatingState } from '@home-automation/deep-heating-types';
import { Option } from 'effect';
import type { Readable } from 'svelte/store';
import { derived } from 'svelte/store';
import { apiClientStore, type WebSocketClient } from './apiClient';

interface Home {
  connected: boolean;
  state: Option.Option<DeepHeatingState>;
}

export const homeStore = derived<Readable<WebSocketClient | null>, Home>(
  apiClientStore,
  ($apiClient, set, update) => {
    if (!$apiClient) {
      set({ connected: false, state: Option.none() });
      return;
    }

    // Subscribe to connected state
    const unsubConnect = $apiClient.connected.subscribe((connected) => {
      update((current) => ({ ...current, connected }));
    });

    // Subscribe to state updates (message.data is already decoded by apiClient)
    const unsubState = $apiClient.state.subscribe((message) => {
      if (message?.type === 'state') {
        update((current) => ({
          ...current,
          state: Option.some(message.data),
        }));
      }
    });

    // Cleanup subscriptions on destroy
    return () => {
      unsubConnect();
      unsubState();
    };
  },
  { connected: false, state: Option.none() },
);
