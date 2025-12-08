import { describe, expect, it } from 'bun:test';
import { Either } from 'effect';
import {
  decodeTemperature,
  RoomAdjustment,
  RoomMode,
  RoomTargetTemperature,
} from '@home-automation/deep-heating-types';
import { getTargetTemperature } from './roomTargetTemperatures';

describe('getTargetTemperature', () => {
  const roomName = 'Living Room';

  const makeScheduledTemp = (
    name: string,
    temp: number,
  ): RoomTargetTemperature => ({
    roomName: name,
    targetTemperature: decodeTemperature(temp),
  });

  const makeRoomMode = (name: string, mode: RoomMode['mode']): RoomMode => ({
    roomName: name,
    mode,
  });

  const makeAdjustment = (
    name: string,
    adjustment: number,
  ): RoomAdjustment => ({
    roomName: name,
    adjustment,
  });

  it('returns Either.left when room names mismatch', () => {
    const result = getTargetTemperature(
      makeScheduledTemp(roomName, 20),
      makeRoomMode(roomName, 'Auto'),
      makeAdjustment('Kitchen', 0), // Mismatched!
    );

    expect(Either.isLeft(result)).toBe(true);
    Either.match(result, {
      onLeft: (error) => {
        expect(error).toMatchObject({ _tag: 'MismatchedRoomNames' });
      },
      onRight: () => {
        expect.unreachable('Expected Either.left');
      },
    });
  });

  it('returns Either.right(temperature) in Auto mode with adjustment', () => {
    const result = getTargetTemperature(
      makeScheduledTemp(roomName, 20),
      makeRoomMode(roomName, 'Auto'),
      makeAdjustment(roomName, 2),
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBe(22);
    }
  });

  it('returns Either.right(MinimumRoomTargetTemperature) in Sleeping mode', () => {
    const result = getTargetTemperature(
      makeScheduledTemp(roomName, 20),
      makeRoomMode(roomName, 'Sleeping'),
      makeAdjustment(roomName, 0),
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBe(15); // MinimumRoomTargetTemperature
    }
  });

  it('returns Either.right(MinimumTrvTargetTemperature) in Off mode', () => {
    const result = getTargetTemperature(
      makeScheduledTemp(roomName, 20),
      makeRoomMode(roomName, 'Off'),
      makeAdjustment(roomName, 0),
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBe(7); // MinimumTrvTargetTemperature
    }
  });

  it('clamps temperature to minimum in Auto mode', () => {
    const result = getTargetTemperature(
      makeScheduledTemp(roomName, 8),
      makeRoomMode(roomName, 'Auto'),
      makeAdjustment(roomName, -5), // Would be 3, but clamped to 15
    );

    expect(Either.isRight(result)).toBe(true);
    if (Either.isRight(result)) {
      expect(result.right).toBe(15); // MinimumRoomTargetTemperature
    }
  });
});
