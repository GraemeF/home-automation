import type { KnipConfig } from 'knip';

const config: KnipConfig = {
  workspaces: {
    // Root workspace - the monorepo itself
    '.': {
      ignore: ['dist/**'],
      ignoreDependencies: [
        // DevDeps used by workspace packages or tooling
        '@testing-library/svelte',
        '@tsconfig/svelte',
        'prettier-plugin-svelte',
        // Used by deep-heating-web via $packages path alias (must be at root for hoisting)
        'svelte-material-icons',
      ],
    },

    // Library packages with standard structure
    'packages/rxx': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },
    'packages/dictionary': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },
    'packages/deep-heating-types': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },
    'packages/deep-heating-home-assistant': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },
    'packages/deep-heating-rx': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },
    'packages/deep-heating-state': {
      entry: ['src/index.ts'],
      ignore: ['dist/**'],
    },

    // WebSocket server application
    'packages/deep-heating-server': {
      entry: ['src/main.ts', 'src/index.ts', 'src/environments/*.ts'],
      ignore: ['dist/**'],
    },

    // SvelteKit web application
    'packages/deep-heating-web': {
      entry: [
        'src/**/*.svelte',
        'src/routes/**/*.ts',
        'src/lib/**/*.ts',
        'src/app.d.ts',
      ],
      ignore: ['dist/**', '.svelte-kit/**'],
    },

    // Combined deployment package
    'packages/deep-heating': {
      entry: ['scripts/*.ts', 'smoke-test.test.ts'],
      ignore: ['dist/**'],
      // These are workspace deps for deployment
      ignoreDependencies: [
        'deep-heating-server',
        '@home-automation/deep-heating-web',
      ],
    },
  },

  // Global ignores
  ignore: [
    '**/dist/**',
    '**/.svelte-kit/**',
    '**/node_modules/**',
    // Ignore old Jest configs until they're cleaned up
    '**/tsconfig.spec.json',
    '**/jest.config.ts',
  ],

  // Ignore binaries that are expected to be used via npx or in CI
  ignoreBinaries: ['only-allow', 'diff'],

  // SvelteKit path aliases - resolved at build time
  ignoreUnresolved: [/^\$lib\//, /^\$packages\//, /^\.\/\$types$/],

  // Rules configuration
  rules: {
    // Package entry files (main/exports in package.json) point to dist/ which only exists after build
    // Don't fail on missing dist files - we analyze source, not built output
    unlisted: 'error',
    unresolved: 'error',
  },

  // Ignore dependencies that should be cleaned up separately (tracked as future work)
  ignoreDependencies: [
    'c8', // Old coverage tool
    'ts-node', // Replaced by bun
    'webpack-merge', // Legacy
    'eslint-plugin-expect-type', // May not be in use
    'eslint-plugin-testing-library', // May not be in use
  ],
};

export default config;
