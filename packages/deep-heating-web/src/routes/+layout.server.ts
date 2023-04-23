import type { LayoutServerLoad } from './$types';
import type { AppSettings } from '$lib/stores/appsettings';

export const load: LayoutServerLoad<AppSettings> = () => ({
  apiUrl: process.env['API_URL'],
});
