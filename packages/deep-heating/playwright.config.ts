import { defineConfig, devices } from '@playwright/test';
import { resolve } from 'path';

const SERVER_PORT = 3099;
const WEB_PORT = 5199;

const PROJECT_ROOT = resolve(__dirname, '../..');
const SMOKE_TEST_HOME_CONFIG = resolve(
  __dirname,
  'fixtures/smoke-test-home.json',
);

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI
    ? [
        ['github'],
        ['html', { open: 'never' }],
        ['json', { outputFile: 'playwright-results.json' }],
      ]
    : 'list',
  timeout: 30_000,

  use: {
    ...devices['Desktop Chrome'],
    baseURL: `http://localhost:${WEB_PORT}`,
    trace: 'on-first-retry',
    headless: true,
  },

  webServer: [
    {
      command: `bun run ${PROJECT_ROOT}/packages/deep-heating-server/src/main.ts`,
      port: SERVER_PORT,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        PORT: String(SERVER_PORT),
        SUPERVISOR_URL: 'http://dummy:8123',
        SUPERVISOR_TOKEN: 'dummy-token-for-smoke-test',
        HOME_CONFIG_PATH: SMOKE_TEST_HOME_CONFIG,
      },
    },
    {
      command: `bun run --cwd ${PROJECT_ROOT}/packages/deep-heating-web preview --port ${WEB_PORT}`,
      port: WEB_PORT,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      stdout: 'pipe',
      stderr: 'pipe',
      env: {
        API_URL: `http://localhost:${SERVER_PORT}`,
      },
    },
  ],
});
