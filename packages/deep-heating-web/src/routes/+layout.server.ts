import type { LayoutServerLoad } from './$types';
import type { AppSettings } from '$lib/stores/appsettings';

export const load: LayoutServerLoad<AppSettings> = () => {
  if (!process.env['API_URL']) throw new Error('API_URL not set');
  return {
    apiUrl: process.env['API_URL'],
  };
};
