import { Effect, Schema } from 'effect';
import { appSettingsStore } from '$lib/stores/appsettings';
import { derived, writable, type Readable } from 'svelte/store';
import {
  ClientMessage,
  type RoomAdjustment,
  ServerMessage,
} from '@home-automation/deep-heating-types';

// =============================================================================
// Types
// =============================================================================

export interface WebSocketClient {
  readonly connected: Readable<boolean>;
  readonly state: Readable<typeof ServerMessage.Type | null>;
  readonly send: (message: typeof ClientMessage.Type) => void;
  readonly adjustRoom: (adjustment: RoomAdjustment) => void;
}

// =============================================================================
// WebSocket Client Factory
// =============================================================================

const createWebSocketClient = (wsUrl: string): WebSocketClient => {
  const connected = writable(false);
  const state = writable<typeof ServerMessage.Type | null>(null);
  // eslint-disable-next-line functional/no-let -- WebSocket client requires mutable state for connection management
  let socket: WebSocket | null = null;
  // eslint-disable-next-line functional/no-let -- Reconnection logic requires mutable counter
  let reconnectAttempts = 0;
  // eslint-disable-next-line functional/no-let -- Timeout reference must be mutable for cleanup
  let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;

  const getReconnectDelay = () => {
    const baseDelay = 1000;
    const maxDelay = 30000;
    const delay = Math.min(
      baseDelay * Math.pow(2, reconnectAttempts),
      maxDelay,
    );
    return delay + Math.random() * 1000; // Add jitter
  };

  const connect = () => {
    if (
      socket?.readyState === WebSocket.OPEN ||
      socket?.readyState === WebSocket.CONNECTING
    ) {
      return;
    }

    try {
      socket = new WebSocket(wsUrl);

      // eslint-disable-next-line functional/immutable-data -- WebSocket API requires callback assignment
      socket.onopen = () => {
        connected.set(true);
        reconnectAttempts = 0;
      };

      // eslint-disable-next-line functional/immutable-data -- WebSocket API requires callback assignment
      socket.onclose = () => {
        connected.set(false);
        socket = null;
        scheduleReconnect();
      };

      // eslint-disable-next-line functional/immutable-data -- WebSocket API requires callback assignment
      socket.onerror = () => {
        // Error will trigger onclose, which handles reconnection
      };

      // eslint-disable-next-line functional/immutable-data -- WebSocket API requires callback assignment
      socket.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data) as unknown;
          const decode = Schema.decodeUnknown(ServerMessage);
          // eslint-disable-next-line effect/no-runSync -- WebSocket callback is a sync boundary
          const message = Effect.runSync(decode(data));
          state.set(message);
        } catch {
          // Ignore invalid messages
        }
      };
    } catch {
      scheduleReconnect();
    }
  };

  const scheduleReconnect = () => {
    if (reconnectTimeout) {
      clearTimeout(reconnectTimeout);
    }
    const delay = getReconnectDelay();
    reconnectAttempts++;
    reconnectTimeout = setTimeout(connect, delay);
  };

  const send = (message: typeof ClientMessage.Type) => {
    if (socket?.readyState === WebSocket.OPEN) {
      const encode = Schema.encode(ClientMessage);
      // eslint-disable-next-line effect/no-runSync -- WebSocket send is a sync boundary
      const encoded = Effect.runSync(encode(message));
      socket.send(JSON.stringify(encoded));
    }
  };

  const adjustRoom = (adjustment: RoomAdjustment) => {
    send({ type: 'adjust_room', data: adjustment });
  };

  // Start connection
  connect();

  return {
    connected: { subscribe: connected.subscribe },
    state: { subscribe: state.subscribe },
    send,
    adjustRoom,
  };
};

// =============================================================================
// Store
// =============================================================================

const buildWebSocketUrl = (apiUrl: string | undefined): string => {
  // Default to current host with /ws path
  if (!apiUrl) {
    const protocol =
      typeof window !== 'undefined' && window.location.protocol === 'https:'
        ? 'wss:'
        : 'ws:';
    const host =
      typeof window !== 'undefined' ? window.location.host : 'localhost:5123';
    return `${protocol}//${host}/ws`;
  }

  // If apiUrl starts with http(s), convert to ws(s)
  if (apiUrl.startsWith('http://')) {
    return apiUrl.replace('http://', 'ws://').replace(/\/?$/, '/ws');
  }
  if (apiUrl.startsWith('https://')) {
    return apiUrl.replace('https://', 'wss://').replace(/\/?$/, '/ws');
  }

  // If apiUrl is a relative path (e.g., "/api"), use current host
  const protocol =
    typeof window !== 'undefined' && window.location.protocol === 'https:'
      ? 'wss:'
      : 'ws:';
  const host =
    typeof window !== 'undefined' ? window.location.host : 'localhost:5123';
  return `${protocol}//${host}${apiUrl}/ws`;
};

export const apiClientStore = derived(appSettingsStore, ($appSettings) =>
  $appSettings
    ? createWebSocketClient(buildWebSocketUrl($appSettings.apiUrl))
    : null,
);
