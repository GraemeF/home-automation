import type { AppSettings } from '$lib/stores/appsettings';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad<AppSettings> = () => ({
  apiUrl: process.env['API_URL'],
});
