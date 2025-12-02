import { describe, expect, test } from 'bun:test';
import {
  GenericContainer,
  Wait,
  type StartedTestContainer,
} from 'testcontainers';

const INGRESS_PORT = 8099;

describe('smoke test', () => {
  test(
    'frontend and backend communicate through nginx',
    async () => {
      const imageName = process.env.SMOKE_TEST_IMAGE;
      if (!imageName) {
        throw new Error(
          'SMOKE_TEST_IMAGE environment variable is required. ' +
            'Set it to the Docker image to test, e.g. SMOKE_TEST_IMAGE=deep-heating:v0.1.0',
        );
      }

      let container: StartedTestContainer | undefined;

      try {
        console.log(`Starting container from image: ${imageName}`);
        container = await new GenericContainer(imageName)
          .withExposedPorts(INGRESS_PORT)
          .withEnvironment({
            SUPERVISOR_URL: 'http://dummy:8123',
            SUPERVISOR_TOKEN: 'dummy-token-for-smoke-test',
            ALLOW_ALL_IPS: 'true',
          })
          .withWaitStrategy(Wait.forHttp('/', INGRESS_PORT).forStatusCode(200))
          .withStartupTimeout(45_000)
          .start();
        console.log('Container started successfully');

        const host = container.getHost();
        const port = container.getMappedPort(INGRESS_PORT);
        const baseUrl = `http://${host}:${port}`;

        // Verify frontend serves
        const frontendResponse = await fetch(baseUrl);
        expect(frontendResponse.ok).toBe(true);
        expect(frontendResponse.headers.get('content-type')).toContain(
          'text/html',
        );

        // Debug: Check what /ws returns via HTTP first
        console.log('Testing /ws endpoint via HTTP...');
        const wsHttpResponse = await fetch(`${baseUrl}/ws`);
        console.log(`  /ws HTTP status: ${wsHttpResponse.status}`);
        console.log(
          `  /ws HTTP headers: ${JSON.stringify(Object.fromEntries(wsHttpResponse.headers))}`,
        );
        if (!wsHttpResponse.ok && wsHttpResponse.status !== 426) {
          const body = await wsHttpResponse.text();
          console.log(`  /ws HTTP body: ${body.slice(0, 500)}`);
        }

        // Verify WebSocket endpoint is routed through nginx
        const wsUrl = `ws://${host}:${port}/ws`;
        console.log(`Testing WebSocket connection to ${wsUrl}...`);
        const wsConnected = await testWebSocketConnection(wsUrl);
        if (!wsConnected) {
          // Dump container logs to help debug
          console.log('WebSocket connection failed! Container logs:');
          const logs = await container.logs();
          const logOutput = await streamToString(logs);
          console.log(logOutput.slice(-5000)); // Last 5000 chars
        }
        expect(wsConnected).toBe(true);
      } finally {
        if (container) {
          await container.stop();
        }
      }
    },
    { timeout: 60_000 },
  );
});

async function streamToString(stream: NodeJS.ReadableStream): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString('utf8');
}

async function testWebSocketConnection(url: string): Promise<boolean> {
  return new Promise((resolve) => {
    const ws = new WebSocket(url);
    const timeout = setTimeout(() => {
      ws.close();
      resolve(false);
    }, 10_000);

    ws.onopen = () => {
      clearTimeout(timeout);
      ws.close();
      resolve(true);
    };

    ws.onerror = () => {
      clearTimeout(timeout);
      ws.close();
      resolve(false);
    };
  });
}
