import { describe, test, beforeAll, afterAll } from 'bun:test';
import {
  GenericContainer,
  Wait,
  type StartedTestContainer,
} from 'testcontainers';
import { chromium, type Browser } from 'playwright';
import { resolve } from 'path';
import {
  testFrontendLoadsWithoutJsErrors,
  testWebSocketConnectionEstablished,
  testUiRendersBasicStructure,
} from './shared-e2e-tests';

const INGRESS_PORT = 8099;

const SMOKE_TEST_HOME_CONFIG = resolve(
  import.meta.dirname,
  'fixtures/smoke-test-home.json',
);

describe('E2E smoke test with Docker', () => {
  let container: StartedTestContainer | undefined;
  let browser: Browser | undefined;
  let baseUrl: string;

  beforeAll(async () => {
    const imageName = process.env.SMOKE_TEST_IMAGE;
    if (!imageName) {
      throw new Error(
        'SMOKE_TEST_IMAGE environment variable is required. ' +
          'Set it to the Docker image to test, e.g. SMOKE_TEST_IMAGE=deep-heating:v0.1.0',
      );
    }

    console.log(`Starting container from image: ${imageName}`);
    console.log(`Using home config: ${SMOKE_TEST_HOME_CONFIG}`);

    container = await new GenericContainer(imageName)
      .withExposedPorts(INGRESS_PORT)
      .withEnvironment({
        SUPERVISOR_URL: 'http://dummy:8123',
        SUPERVISOR_TOKEN: 'dummy-token-for-smoke-test',
        ALLOW_ALL_IPS: 'true',
        HOME_CONFIG_PATH: '/config/home.json',
      })
      .withCopyFilesToContainer([
        {
          source: SMOKE_TEST_HOME_CONFIG,
          target: '/config/home.json',
        },
      ])
      .withWaitStrategy(Wait.forHttp('/', INGRESS_PORT).forStatusCode(200))
      .withStartupTimeout(45_000)
      .start();

    const host = container.getHost();
    const port = container.getMappedPort(INGRESS_PORT);
    baseUrl = `http://${host}:${port}`;
    console.log(`Container started at ${baseUrl}`);

    console.log('Launching Playwright browser...');
    browser = await chromium.launch({ headless: true });
    console.log('Browser launched');
  }, 90_000);

  afterAll(async () => {
    if (browser) {
      await browser.close();
      console.log('Browser closed');
    }
    if (container) {
      await container.stop();
      console.log('Container stopped');
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
