import { Schema } from 'effect';
import { DeepHeatingState } from './deep-heating-types';

// =============================================================================
// Room Adjustment Schema
// =============================================================================

export const RoomAdjustmentSchema = Schema.Struct({
  roomName: Schema.String,
  adjustment: Schema.Number,
});
export type RoomAdjustmentSchemaType = typeof RoomAdjustmentSchema.Type;

// =============================================================================
// WebSocket Message Schemas
// =============================================================================

export const ServerStateMessage = Schema.Struct({
  type: Schema.Literal('state'),
  data: DeepHeatingState,
});
export type ServerStateMessage = typeof ServerStateMessage.Type;

export const ServerMessage = Schema.Union(ServerStateMessage);
export type ServerMessage = typeof ServerMessage.Type;
export type ServerMessageEncoded = typeof ServerMessage.Encoded;

export const ClientAdjustRoomMessage = Schema.Struct({
  type: Schema.Literal('adjust_room'),
  data: RoomAdjustmentSchema,
});
export type ClientAdjustRoomMessage = typeof ClientAdjustRoomMessage.Type;

export const ClientMessage = Schema.Union(ClientAdjustRoomMessage);
export type ClientMessage = typeof ClientMessage.Type;
export type ClientMessageEncoded = typeof ClientMessage.Encoded;
