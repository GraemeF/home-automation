import { appSettingsStore } from '$lib/stores/appsettings';
import ioClient from 'socket.io-client';
import { derived } from 'svelte/store';

export const apiClientStore = derived(appSettingsStore, ($appSettings) =>
  $appSettings ? createClient($appSettings?.apiUrl) : null,
);

const createClient = (apiUrl: string | undefined) => {
  if (!apiUrl) {
    return ioClient();
  }
  if (apiUrl.startsWith('http://') || apiUrl.startsWith('https://')) {
    return ioClient(apiUrl);
  }
  return ioClient({ path: `${apiUrl}/socket.io/` });
};
