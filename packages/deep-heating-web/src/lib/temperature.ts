import { Schema } from 'effect';
import { Temperature } from '@home-automation/deep-heating-types';
import { Option, pipe } from 'effect';

const formatter = new Intl.NumberFormat('en-GB', {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

export const formatTemperature = (
  temperature: Option.Option<Temperature>,
  showUnits = true,
): string =>
  pipe(
    temperature,
    Option.match({
      onSome: (t) => formatter.format(t) + (showUnits ? 'ºC' : ''),
      onNone: () => '–',
    }),
  );

const VeryHot = pipe(60, Schema.decodeUnknown(Temperature));

const getTemperatureFromRoom = (room: {
  temperature: Option.Option<{ temperature: Temperature }>;
}) =>
  pipe(
    room.temperature,
    Option.getOrElse(() => VeryHot),
  );

export const compareByRoomTemperature = (
  a: { temperature: Option.Option<{ temperature: Temperature }> },
  b: { temperature: Option.Option<{ temperature: Temperature }> },
) =>
  getTemperatureFromRoom(a) > getTemperatureFromRoom(b)
    ? 1
    : getTemperatureFromRoom(a) < getTemperatureFromRoom(b)
      ? -1
      : 0;
