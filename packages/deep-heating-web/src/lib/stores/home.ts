import { Schema } from 'effect';
import { DeepHeatingState } from '@home-automation/deep-heating-types';
import { Option, pipe } from 'effect';
import type { Readable } from 'svelte/store';
import { derived } from 'svelte/store';
import { apiClientStore, type WebSocketClient } from './apiClient';

interface Home {
  connected: boolean;
  state: Option.Option<DeepHeatingState>;
}

export const homeStore = derived<Readable<WebSocketClient | null>, Home>(
  apiClientStore,
  ($apiClient, set) => {
    if (!$apiClient) {
      set({ connected: false, state: Option.none() });
      return;
    }

    // Subscribe to connected state
    const unsubConnect = $apiClient.connected.subscribe((connected) => {
      set((current: Home) => ({ ...current, connected }));
    });

    // Subscribe to state updates
    const unsubState = $apiClient.state.subscribe((message) => {
      if (message?.type === 'state') {
        set((current: Home) => ({
          ...current,
          state: pipe(
            message.data,
            Schema.decodeUnknownSync(DeepHeatingState),
            Option.some,
          ),
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
