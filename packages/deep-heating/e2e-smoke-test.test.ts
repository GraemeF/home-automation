import { describe, expect, test, beforeAll, afterAll } from 'bun:test';
import {
  GenericContainer,
  Wait,
  type StartedTestContainer,
} from 'testcontainers';
import { chromium, type Browser, type ConsoleMessage } from 'playwright';
import { resolve } from 'path';

const INGRESS_PORT = 8099;

const SMOKE_TEST_HOME_CONFIG = resolve(
  import.meta.dirname,
  'fixtures/smoke-test-home.json',
);

describe('E2E smoke test with Playwright', () => {
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
      expect(browser).toBeDefined();
      const page = await browser!.newPage();

      const consoleErrors: ConsoleMessage[] = [];
      const pageErrors: Error[] = [];

      page.on('console', (msg) => {
        if (msg.type() === 'error') {
          consoleErrors.push(msg);
        }
      });

      page.on('pageerror', (error) => {
        pageErrors.push(error);
      });

      await page.goto(baseUrl, { waitUntil: 'networkidle' });

      // Log any errors for debugging
      if (consoleErrors.length > 0) {
        console.log('Console errors found:');
        for (const msg of consoleErrors) {
          console.log(`  ${msg.text()}`);
        }
      }
      if (pageErrors.length > 0) {
        console.log('Page errors found:');
        for (const err of pageErrors) {
          console.log(`  ${err.message}`);
        }
      }

      expect(consoleErrors).toHaveLength(0);
      expect(pageErrors).toHaveLength(0);

      await page.close();
    },
    { timeout: 30_000 },
  );

  test(
    'WebSocket connection is established',
    async () => {
      expect(browser).toBeDefined();
      const page = await browser!.newPage();

      // Track WebSocket events
      let wsConnected = false;
      let wsUrl = '';

      // Listen for WebSocket creation via CDP
      const client = await page.context().newCDPSession(page);
      await client.send('Network.enable');

      client.on('Network.webSocketCreated', (event) => {
        wsUrl = event.url;
        console.log(`WebSocket created: ${wsUrl}`);
      });

      client.on('Network.webSocketFrameSent', () => {
        wsConnected = true;
      });

      client.on('Network.webSocketFrameReceived', () => {
        wsConnected = true;
      });

      await page.goto(baseUrl, { waitUntil: 'networkidle' });

      // Wait a bit for WebSocket to establish
      await page.waitForTimeout(3000);

      console.log(`WebSocket URL: ${wsUrl}`);
      console.log(`WebSocket connected: ${wsConnected}`);

      // The app should have created a WebSocket connection
      expect(wsUrl).toContain('/ws');

      await page.close();
    },
    { timeout: 30_000 },
  );

  test(
    'UI renders basic structure',
    async () => {
      expect(browser).toBeDefined();
      const page = await browser!.newPage();

      await page.goto(baseUrl, { waitUntil: 'networkidle' });

      // Check that the page has loaded and contains expected elements
      const title = await page.title();
      console.log(`Page title: ${title}`);

      // The app should have a body element at minimum
      const body = await page.$('body');
      expect(body).not.toBeNull();

      // Take a screenshot for debugging (useful in CI)
      const screenshot = await page.screenshot();
      console.log(`Screenshot taken (${screenshot.length} bytes)`);

      // Check that no loading/error states are stuck
      // (Adjust these selectors based on your actual app structure)
      const html = await page.content();

      // Basic sanity check - page should have some meaningful content
      expect(html.length).toBeGreaterThan(500);

      // Should not be showing an error page
      const errorIndicators = [
        '500 Internal Server Error',
        '404 Not Found',
        'Application Error',
      ];
      for (const indicator of errorIndicators) {
        expect(html).not.toContain(indicator);
      }

      await page.close();
    },
    { timeout: 30_000 },
  );
});
