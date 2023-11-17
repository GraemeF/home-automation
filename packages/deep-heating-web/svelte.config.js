import adapter from '@sveltejs/adapter-node';
import preprocess from 'svelte-preprocess';
import * as path from 'path';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  // Consult https://github.com/sveltejs/svelte-preprocess
  // for more information about preprocessors
  preprocess: preprocess({
    postcss: true,
  }),

  kit: {
    adapter: adapter({ out: '../../dist/packages/deep-heating-web' }),
    alias: {
      '@home-automation/deep-heating-types': path.resolve(
        '../deep-heating-types/src/index.ts',
      ),
      $packages: path.resolve('../../node_modules'),
    },
  },
};

export default config;
