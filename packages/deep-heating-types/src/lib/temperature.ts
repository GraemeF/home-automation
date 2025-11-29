import { Schema } from 'effect';
import { pipe } from 'effect';

export const Temperature = pipe(
  Schema.Number,
  Schema.between(-20, 60),
  Schema.brand('ºC'),
);
export type Temperature = typeof Temperature.Type;
