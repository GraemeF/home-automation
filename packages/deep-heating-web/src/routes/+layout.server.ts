import type { AppSettings } from '$lib/stores/appsettings';
import type { LayoutServerLoad } from './$types';

const getApiUrl = (request: Request) => {
  if (process.env['API_URL']) {
    console.log('Using API_URL', process.env['API_URL']);
    return process.env['API_URL'];
  }

  if (request.headers.get('X-Ingress-Path')) {
    console.log('Using X-Ingress-Path', request.headers.get('X-Ingress-Path'));
    return request.headers.get('X-Ingress-Path') ?? undefined;
  }

  console.log('No API URL specified');
  return undefined;
};

export const load: LayoutServerLoad<AppSettings> = ({ request }) => {
  return {
    apiUrl: getApiUrl(request),
  };
};
