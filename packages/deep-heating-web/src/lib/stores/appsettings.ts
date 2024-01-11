import { writable } from 'svelte/store';

export type AppSettings = {
  apiUrl: string | undefined;
};

export const appSettingsStore = writable<AppSettings | undefined>(undefined);
