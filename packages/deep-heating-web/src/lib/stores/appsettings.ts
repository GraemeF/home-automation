import { writable } from 'svelte/store';

export type AppSettings = {
  apiUrl: string;
};

export const appSettingsStore = writable<AppSettings | undefined>(undefined);
