import { appSettingsStore } from '$lib/stores/appsettings';
import ioClient from 'socket.io-client';
import { derived } from 'svelte/store';

export const apiClientStore = derived(appSettingsStore, ($appSettings) =>
  $appSettings ? createClient($appSettings?.apiUrl) : null,
);

const createClient = (apiUrl: string | undefined) =>
  apiUrl ? ioClient(apiUrl) : ioClient();
