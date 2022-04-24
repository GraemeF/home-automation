import ioClient from 'socket.io-client';
import { derived } from 'svelte/store';
import { appSettingsStore } from '$lib/stores/appsettings';

export const apiClientStore = derived(appSettingsStore, ($appSettings) => {
  const { apiUrl } = $appSettings ?? { apiUrl: undefined };

  if (apiUrl) return ioClient(apiUrl);
  else return null;
});
