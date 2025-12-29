import { test, expect } from '@playwright/test';

test.describe('E2E smoke test with local services', () => {
  test('frontend loads without JavaScript errors', async ({ page }) => {
    const consoleErrors: string[] = [];
    const pageErrors: string[] = [];

    page.on('console', (msg) => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    page.on('pageerror', (error) => {
      pageErrors.push(error.message);
    });

    await page.goto('/', { waitUntil: 'networkidle' });

    if (consoleErrors.length > 0) {
      console.log('Console errors found:');
      for (const msg of consoleErrors) {
        console.log(`  ${msg}`);
      }
    }
    if (pageErrors.length > 0) {
      console.log('Page errors found:');
      for (const err of pageErrors) {
        console.log(`  ${err}`);
      }
    }

    expect(consoleErrors).toHaveLength(0);
    expect(pageErrors).toHaveLength(0);
  });

  test('WebSocket connection is established', async ({ page }) => {
    let wsUrl = '';

    const client = await page.context().newCDPSession(page);
    await client.send('Network.enable');

    client.on('Network.webSocketCreated', (event) => {
      wsUrl = event.url;
      console.log(`WebSocket created: ${wsUrl}`);
    });

    await page.goto('/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);

    console.log(`WebSocket URL: ${wsUrl}`);
    expect(wsUrl).toContain('/ws');
  });

  test('UI renders basic structure', async ({ page }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    const title = await page.title();
    console.log(`Page title: ${title}`);

    const body = await page.$('body');
    expect(body).not.toBeNull();

    const screenshot = await page.screenshot();
    console.log(`Screenshot taken (${screenshot.length} bytes)`);

    const html = await page.content();
    expect(html.length).toBeGreaterThan(500);

    const errorIndicators = [
      '500 Internal Server Error',
      '404 Not Found',
      'Application Error',
    ];
    for (const indicator of errorIndicators) {
      expect(html).not.toContain(indicator);
    }
  });

  test('pop-out button is hidden by default (feature flag off)', async ({
    page,
  }) => {
    await page.goto('/', { waitUntil: 'networkidle' });

    const popOutButton = page.getByRole('button', { name: /pop.?out/i });
    await expect(popOutButton).not.toBeVisible();
  });
});
