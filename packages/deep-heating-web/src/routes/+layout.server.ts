import type { AppSettings } from '$lib/stores/appsettings';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad<AppSettings> = () => {
  if (!process.env['API_URL']) throw new Error('API_URL not set');
  return {
    apiUrl: process.env['API_URL'],
  };
};
