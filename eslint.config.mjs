import typescript from '@typescript-eslint/eslint-plugin';
import parser from '@typescript-eslint/parser';
import unusedImports from 'eslint-plugin-unused-imports';
import prettier from 'eslint-config-prettier';
import functionalPlugin from 'eslint-plugin-functional';
import sveltePlugin from 'eslint-plugin-svelte';
import svelteParser from 'svelte-eslint-parser';
import compatPlugin from 'eslint-plugin-compat';
import effectPlugin from '@codeforbreakfast/eslint-effect';

// Shared parser configuration
const commonLanguageOptions = {
  parser,
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
};

const commonLanguageOptionsWithProject = {
  ...commonLanguageOptions,
  parserOptions: {
    ...commonLanguageOptions.parserOptions,
    projectService: true,
  },
};

// Common plugins for TypeScript files
const commonPlugins = {
  '@typescript-eslint': typescript,
  'unused-imports': unusedImports,
  effect: {
    rules: effectPlugin.rules,
  },
};

const functionalPluginOnly = {
  functional: functionalPlugin,
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

// Test functional rules - relaxed for test files
const testFunctionalRules = {
  'functional/no-let': 'off',
  'functional/immutable-data': 'off',
  'functional/prefer-readonly-type': 'error',
  'functional/no-loop-statements': 'error',
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
  // Functional immutability rules (excludes tests)
  // Based on effectPlugin's config but extended with RxJS patterns
  {
    name: 'functional-immutability',
    files: ['**/*.ts', '**/*.tsx'],
    ignores: [
      '**/*.test.ts',
      '**/*.test.tsx',
      '**/*.spec.ts',
      '**/*.spec.tsx',
      '**/tests/**',
      '**/testing/**',
    ],
    languageOptions: commonLanguageOptionsWithProject,
    plugins: functionalPluginOnly,
    rules: {
      ...effectPlugin.configs.functionalImmutabilityRules,
      // Disable type-declaration-immutability - the I.+ heuristic (assuming I = Interface)
      // is too blunt and triggers false positives on Input*, Item*, Index*, etc.
      // Schema-derived types are already immutable at runtime anyway.
      'functional/type-declaration-immutability': 'off',
      // Override prefer-immutable-types to include RxJS patterns
      'functional/prefer-immutable-types': [
        'error',
        {
          enforcement: 'ReadonlyShallow',
          ignoreInferredTypes: true,
          ignoreTypePattern: [
            // Effect types (from effectPlugin config)
            '^Ref\\.Ref<.*>$',
            '^Queue\\.Queue<.*>$',
            '^HashMap\\.HashMap<.*>$',
            '^HashSet\\.HashSet<.*>$',
            '^Stream\\.Stream<.*>$',
            '^PubSub\\.PubSub<.*>$',
            'ServerWebSocket<.*>$',
            '^ReadonlyDeep<Date>$',
            // RxJS types - Observable has methods but is functionally immutable
            '^Observable<.*>$',
            '^Subject<.*>$',
            '^BehaviorSubject<.*>$',
            '^ReplaySubject<.*>$',
            '^MonoTypeOperatorFunction<.*>$',
            '^OperatorFunction<.*>$',
            '^UnaryFunction<.*>$',
          ],
          parameters: {
            enforcement: 'ReadonlyShallow',
          },
        },
      ],
    },
  },
  // TypeScript files (all packages)
  {
    name: 'typescript-base',
    files: ['**/*.ts', '**/*.tsx'],
    languageOptions: commonLanguageOptions,
    plugins: commonPlugins,
    rules: typescriptBaseRules,
  },
  // Effect strict rules for all TS files (excludes testing)
  {
    name: 'effect-strict',
    files: ['**/*.ts', '**/*.tsx'],
    ignores: ['**/testing/**'],
    languageOptions: commonLanguageOptions,
    plugins: commonPlugins,
    rules: {
      ...effectPlugin.configs.strict.rules,
      // Disable rules that conflict with RxJS patterns
      'effect/no-method-pipe': 'off', // RxJS uses Observable.pipe()
      'effect/no-if-statement': 'off', // Too strict for RxJS-heavy codebase
    },
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
  // Test files - same Effect rules as production, use bun-test-effect instead of runPromise/runSync
  {
    name: 'test-files',
    files: [
      '**/*.test.ts',
      '**/*.test.tsx',
      '**/*.spec.ts',
      '**/*.spec.tsx',
      '**/testing/**/*.ts',
    ],
    languageOptions: commonLanguageOptions,
    plugins: {
      ...commonPlugins,
      functional: functionalPlugin,
    },
    rules: {
      // Tests should use bun-test-effect (effect(), layer()) instead of runPromise/runSync
      // This keeps test code consistent with production patterns
      ...testFunctionalRules,
    },
  },
  // Scripts - allow runPromise/runSync as entry points
  {
    name: 'scripts',
    files: ['scripts/**/*.ts'],
    languageOptions: commonLanguageOptions,
    rules: {
      // Allow runPromise/runSync in scripts as they are application entry points
      'effect/no-runPromise': 'off',
      'effect/no-runSync': 'off',
    },
  },
  // Web package - relaxed Effect rules (SvelteKit app, not Effect-based)
  {
    name: 'web-package',
    files: ['packages/deep-heating-web/**/*.ts'],
    rules: {
      // SvelteKit SSR uses process.env directly, not Effect's platform abstraction
      'effect/prefer-effect-platform': 'off',
      // Svelte stores are inherently mutable
      'functional/prefer-immutable-types': 'off',
      'functional/prefer-readonly-type': 'off',
    },
  },
  // Server package - Effect-based WebSocket server at application boundary
  {
    name: 'server-package',
    files: ['packages/deep-heating-server/**/*.ts'],
    rules: {
      // Allow Bun.write for fire-and-forget file writes from RxJS callbacks
      'effect/prefer-effect-platform': 'off',
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
