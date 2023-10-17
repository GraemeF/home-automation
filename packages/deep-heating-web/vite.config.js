import { sveltekit } from '@sveltejs/kit/vite';
import checker from 'vite-plugin-checker';

/** @type {import('vite').UserConfig} */
const config = {
  plugins: [sveltekit(), checker({ typescript: true })],
  ssr: process.env.NODE_ENV === 'production' ? {} : undefined,
  server: { fs: { strict: process.env.NODE_ENV === 'production' } },
};

export default config;
