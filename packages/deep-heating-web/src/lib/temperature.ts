import { Schema } from '@effect/schema';
import { Temperature } from '@home-automation/deep-heating-types';
import { Option, pipe } from 'effect';

const formatter = new Intl.NumberFormat('en-GB', {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

export const formatTemperature = (
  temperature?: Temperature,
  showUnits = true
): string =>
  temperature ? formatter.format(temperature) + (showUnits ? 'ºC' : '') : '–';

const VeryHot = Schema.parse(Temperature)(60);

const getTemperatureFromRoom = (room: {
  temperature: Option.Option<{ temperature: Temperature }>;
}) =>
  pipe(
    room.temperature,
    Option.getOrElse(() => VeryHot)
  );

export const compareByRoomTemperature = (
  a: { temperature: Option.Option<{ temperature: Temperature }> },
  b: { temperature: Option.Option<{ temperature: Temperature }> }
) =>
  getTemperatureFromRoom(a) > getTemperatureFromRoom(b)
    ? 1
    : getTemperatureFromRoom(a) < getTemperatureFromRoom(b)
    ? -1
    : 0;
