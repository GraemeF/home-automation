import { ReadonlyArray, ReadonlyRecord, pipe } from 'effect';
import { DateTime, Duration } from 'luxon';
import { HeatingSchedule, HeatingScheduleEntry } from './deep-heating-types';
import { WeekSchedule } from './schedule-types';

function toStartOfDay(
  day: string,
  startOfDay: DateTime,
  offset: Duration,
  notBeforeTime: DateTime
): DateTime {
  return startOfDay.toFormat('cccc').toLowerCase() !== day ||
    startOfDay.plus(offset) < notBeforeTime
    ? toStartOfDay(day, startOfDay.plus({ days: 1 }), offset, notBeforeTime)
    : startOfDay.startOf('day');
}

const byStart = (a: HeatingScheduleEntry, b: HeatingScheduleEntry) =>
  a.start.getTime() < b.start.getTime()
    ? -1
    : a.start.getTime() > b.start.getTime()
    ? 1
    : 0;

export const toHeatingSchedule = (
  schedule: WeekSchedule,
  now: DateTime
): HeatingSchedule => {
  const today = now.startOf('day');
  const futureSlots = ReadonlyRecord.toEntries(schedule)
    .flatMap(([dayName, slots]) =>
      pipe(
        slots,
        ReadonlyRecord.toEntries,
        ReadonlyArray.map(([start, target]) => ({
          start: Duration.fromISOTime(start),
          target,
        })),
        ReadonlyArray.map(({ start, target }) => ({
          start: toStartOfDay(dayName, today, start, now)
            .plus(start)
            .toJSDate(),
          targetTemperature: target,
        }))
      )
    )
    .sort(byStart);

  const currentSlot = futureSlots[futureSlots.length - 1];
  return [
    {
      start: DateTime.fromJSDate(currentSlot.start)
        .minus({ weeks: 1 })
        .toJSDate(),
      targetTemperature: currentSlot.targetTemperature,
    },
    ...futureSlots,
  ];
};
