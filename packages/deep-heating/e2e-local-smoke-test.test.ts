import { describe, test, beforeAll, afterAll } from 'bun:test';
import { chromium, type Browser } from 'playwright';
import { resolve } from 'path';
import { spawn, type Subprocess } from 'bun';
import {
  testFrontendLoadsWithoutJsErrors,
  testWebSocketConnectionEstablished,
  testUiRendersBasicStructure,
} from './shared-e2e-tests';

const SERVER_PORT = 3099;
const WEB_PORT = 5199;

const PROJECT_ROOT = resolve(import.meta.dirname, '../..');
const SMOKE_TEST_HOME_CONFIG = resolve(
  import.meta.dirname,
  'fixtures/smoke-test-home.json',
);

async function waitForServer(
  url: string,
  options: {
    acceptNotFound?: boolean;
    maxAttempts?: number;
    delayMs?: number;
  } = {},
): Promise<void> {
  const { acceptNotFound = false, maxAttempts = 30, delayMs = 1000 } = options;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetch(url);
      // Accept 200 OK always, and 404 if specified (useful for servers without root handler)
      if (response.ok || (acceptNotFound && response.status === 404)) {
        console.log(
          `Server ready at ${url} (attempt ${attempt}, status ${response.status})`,
        );
        return;
      }
    } catch {
      // Server not ready yet
    }
    if (attempt < maxAttempts) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
  throw new Error(
    `Server at ${url} failed to start after ${maxAttempts} attempts`,
  );
}

describe('E2E smoke test with local services', () => {
  let serverProcess: Subprocess | undefined;
  let webProcess: Subprocess | undefined;
  let browser: Browser | undefined;
  let baseUrl: string;

  beforeAll(async () => {
    console.log(`Using home config: ${SMOKE_TEST_HOME_CONFIG}`);
    console.log(`Project root: ${PROJECT_ROOT}`);

    // Start the backend server
    console.log(`Starting backend server on port ${SERVER_PORT}...`);
    serverProcess = spawn({
      cmd: ['bun', 'run', 'packages/deep-heating-server/src/main.ts'],
      cwd: PROJECT_ROOT,
      env: {
        ...process.env,
        PORT: String(SERVER_PORT),
        SUPERVISOR_URL: 'http://dummy:8123',
        SUPERVISOR_TOKEN: 'dummy-token-for-smoke-test',
        HOME_CONFIG_PATH: SMOKE_TEST_HOME_CONFIG,
      },
      stdout: 'inherit',
      stderr: 'inherit',
    });

    // Start the web server
    console.log(`Starting web server on port ${WEB_PORT}...`);
    webProcess = spawn({
      cmd: [
        'bun',
        'run',
        '--cwd',
        'packages/deep-heating-web',
        'preview',
        '--port',
        String(WEB_PORT),
      ],
      cwd: PROJECT_ROOT,
      env: {
        ...process.env,
        API_URL: `http://localhost:${SERVER_PORT}`,
      },
      stdout: 'inherit',
      stderr: 'inherit',
    });

    // Wait for both servers to be ready
    console.log('Waiting for servers to be ready...');
    await Promise.all([
      // Backend server returns 404 on root (it only handles /ws), so accept that
      waitForServer(`http://localhost:${SERVER_PORT}/`, {
        acceptNotFound: true,
      }),
      waitForServer(`http://localhost:${WEB_PORT}/`),
    ]);

    baseUrl = `http://localhost:${WEB_PORT}`;
    console.log(`Services started, baseUrl: ${baseUrl}`);

    console.log('Launching Playwright browser...');
    browser = await chromium.launch({ headless: true });
    console.log('Browser launched');
  }, 120_000);

  afterAll(async () => {
    if (browser) {
      await browser.close();
      console.log('Browser closed');
    }
    if (webProcess) {
      webProcess.kill();
      console.log('Web server stopped');
    }
    if (serverProcess) {
      serverProcess.kill();
      console.log('Backend server stopped');
    }
  });

  test(
    'frontend loads without JavaScript errors',
    async () => {
      await testFrontendLoadsWithoutJsErrors(browser!, baseUrl);
    },
    { timeout: 30_000 },
  );

  test(
    'WebSocket connection is established',
    async () => {
      await testWebSocketConnectionEstablished(browser!, baseUrl);
    },
    { timeout: 30_000 },
  );

  test(
    'UI renders basic structure',
    async () => {
      await testUiRendersBasicStructure(browser!, baseUrl);
    },
    { timeout: 30_000 },
  );
});
