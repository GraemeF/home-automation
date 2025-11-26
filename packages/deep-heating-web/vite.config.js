import { sveltekit } from '@sveltejs/kit/vite';
import checker from 'vite-plugin-checker';

// vite-plugin-checker spawns a worker that can hang in Nix sandbox during builds
// Only enable it in dev mode where it's actually useful
const checkerPlugin =
  process.env.NODE_ENV !== 'production' ? checker({ typescript: true }) : null;

/** @type {import('vite').UserConfig} */
const config = {
  plugins: [sveltekit(), checkerPlugin].filter(Boolean),
  ssr: process.env.NODE_ENV === 'production' ? {} : undefined,
  server: { fs: { strict: process.env.NODE_ENV === 'production' } },
};

export default config;
