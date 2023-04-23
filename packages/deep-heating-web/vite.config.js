import { sveltekit } from '@sveltejs/kit/vite';

/** @type {import('vite').UserConfig} */
const config = {
  plugins: [sveltekit()],
  ssr: process.env.NODE_ENV === 'production' ? {} : undefined,
  server: { fs: { strict: process.env.NODE_ENV === 'production' } },
};

export default config;
