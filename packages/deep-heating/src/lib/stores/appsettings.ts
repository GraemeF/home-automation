import { writable } from 'svelte/store';
import type { AppSettings } from '../../routes/appsettings.json';

export const appSettingsStore = writable<AppSettings | undefined>(undefined);
