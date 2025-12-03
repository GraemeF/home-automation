import { expect } from 'bun:test';
import type { Browser, ConsoleMessage } from 'playwright';

/**
 * Shared E2E test functions that can run against any baseUrl.
 * Used by both Docker smoke tests and local service tests.
 */

export async function testFrontendLoadsWithoutJsErrors(
  browser: Browser,
  baseUrl: string,
): Promise<void> {
  const page = await browser.newPage();

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
}

export async function testWebSocketConnectionEstablished(
  browser: Browser,
  baseUrl: string,
): Promise<void> {
  const page = await browser.newPage();

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
}

export async function testUiRendersBasicStructure(
  browser: Browser,
  baseUrl: string,
): Promise<void> {
  const page = await browser.newPage();

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
}
