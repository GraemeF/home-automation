import { derived } from 'svelte/store';
import type { Readable } from 'svelte/store';
import { apiClientStore } from './apiClient';
import type { DeepHeatingState } from '../deep-heating-types';
import type { Socket } from 'socket.io-client';
import type { DefaultEventsMap } from 'socket.io/dist/typed-events';

export const homeStore = derived<
  Readable<Socket<DefaultEventsMap, DefaultEventsMap>>,
  DeepHeatingState | undefined
>(apiClientStore, ($apiClient, set) => {
  $apiClient.on('connect', () => {
    console.log('connected');
  });

  $apiClient.on('disconnect', () => {
    console.log('disconnected');
  });

  $apiClient.on('State', (state) => {
    set(state);
  });
});
