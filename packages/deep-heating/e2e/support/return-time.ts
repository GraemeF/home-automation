import { Duration } from 'effect';

export type ReturnTime =
  | { readonly _tag: 'duration'; readonly value: Duration.Duration }
  | { readonly _tag: 'specific'; readonly value: Date };

export const duration = (value: Duration.Duration): ReturnTime => ({
  _tag: 'duration',
  value,
});
