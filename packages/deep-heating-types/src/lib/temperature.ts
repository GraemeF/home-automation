import { Schema } from '@effect/schema';
import { pipe } from 'effect';

export const Temperature = pipe(
  Schema.number,
  Schema.between(-20, 60),
  Schema.brand('ºC')
);
export type Temperature = Schema.Schema.To<typeof Temperature>;
