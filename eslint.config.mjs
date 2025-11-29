import typescript from '@typescript-eslint/eslint-plugin';
import parser from '@typescript-eslint/parser';
import unusedImports from 'eslint-plugin-unused-imports';
import prettier from 'eslint-config-prettier';
import functionalPlugin from 'eslint-plugin-functional';
import sveltePlugin from 'eslint-plugin-svelte';
import svelteParser from 'svelte-eslint-parser';
import compatPlugin from 'eslint-plugin-compat';

// Shared parser configuration
const commonLanguageOptions = {
  parser,
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
};

// Common plugins for TypeScript files
const commonPlugins = {
  '@typescript-eslint': typescript,
  'unused-imports': unusedImports,
};

// TypeScript base rules
const typescriptBaseRules = {
  ...typescript.configs['recommended'].rules,
  ...prettier.rules,
  'unused-imports/no-unused-imports': 'error',
  '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
  '@typescript-eslint/explicit-function-return-type': 'off',
  '@typescript-eslint/explicit-module-boundary-types': 'off',
};

export default [
  // Global ignores
  {
    name: 'global-ignores',
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/.svelte-kit/**',
      '**/build/**',
      '**/*.d.ts',
      '**/*.cjs',
      '**/generated/**',
      '**/vite.config.js.timestamp-*.mjs',
    ],
  },
  // TypeScript files (all packages)
  {
    name: 'typescript-base',
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: commonLanguageOptions,
    plugins: commonPlugins,
    rules: typescriptBaseRules,
  },
  // Svelte files (web package)
  {
    name: 'svelte',
    files: ['packages/deep-heating-web/**/*.svelte'],
    languageOptions: {
      parser: svelteParser,
      parserOptions: {
        parser,
        extraFileExtensions: ['.svelte'],
      },
    },
    plugins: {
      ...commonPlugins,
      svelte: sveltePlugin,
      compat: compatPlugin,
    },
    rules: {
      ...typescriptBaseRules,
      ...sveltePlugin.configs.recommended.rules,
    },
  },
  // Source files - functional rules (excludes tests)
  // Note: Rules requiring type info (immutable-data, prefer-immutable-types)
  // need parserOptions.project - disabled for now, can enable with typed linting later
  {
    name: 'source-functional',
    files: ['packages/*/src/**/*.ts'],
    ignores: ['**/*.test.ts', '**/*.spec.ts', '**/*.stories.ts'],
    plugins: {
      functional: functionalPlugin,
    },
    rules: {
      'functional/no-let': 'warn',
      'functional/no-loop-statements': 'warn',
    },
  },
  // Stories files - functional rules
  {
    name: 'stories-functional',
    files: ['**/*.stories.ts'],
    plugins: {
      functional: functionalPlugin,
    },
    rules: {
      'functional/prefer-immutable-types': 'warn',
      'functional/functional-parameters': 'off',
      'functional/immutable-data': 'warn',
      'functional/no-throw-statements': 'warn',
      'functional/no-conditional-statements': 'warn',
      'functional/no-expression-statements': 'off',
      'functional/no-classes': 'warn',
      'functional/no-let': 'off',
      'functional/no-loop-statements': 'warn',
      'functional/no-try-statements': 'warn',
      'functional/no-this-expressions': 'warn',
      'functional/no-return-void': 'off',
    },
  },
];
