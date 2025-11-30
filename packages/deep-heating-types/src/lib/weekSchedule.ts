import { DateTime, Duration } from 'luxon';
import { HeatingSchedule, HeatingScheduleEntry } from './deep-heating-types';
import { DaySchedule, WeekSchedule } from './schedule-types';
import { Temperature } from './temperature';

function toStartOfDay(
  day: string,
  startOfDay: DateTime,
  offset: Duration,
  notBeforeTime: DateTime,
): DateTime {
  // Recursively find the next occurrence of this day that's after notBeforeTime
  const isDifferentDay = startOfDay.toFormat('cccc').toLowerCase() !== day;
  const isBeforeNotBeforeTime = startOfDay.plus(offset) < notBeforeTime;

  // eslint-disable-next-line effect/prefer-match-over-ternary -- Not Effect code, ternary is appropriate
  return isDifferentDay || isBeforeNotBeforeTime
    ? toStartOfDay(day, startOfDay.plus({ days: 1 }), offset, notBeforeTime)
    : startOfDay.startOf('day');
}

const byStart = (a: HeatingScheduleEntry, b: HeatingScheduleEntry) =>
  a.start.getTime() < b.start.getTime()
    ? -1
    : a.start.getTime() > b.start.getTime()
      ? 1
      : 0;

type SlotEntry = readonly [string, Temperature];

function getSlotEntries(slots: DaySchedule): ReadonlyArray<SlotEntry> {
  return Object.entries(slots) as ReadonlyArray<SlotEntry>;
}

export const toHeatingSchedule = (
  schedule: WeekSchedule,
  now: DateTime,
): HeatingSchedule => {
  const today = now.startOf('day');
  const scheduleEntries = Object.entries(schedule) as ReadonlyArray<
    readonly [string, DaySchedule]
  >;

  const futureSlots = scheduleEntries.flatMap(([dayName, slots]) => {
    const slotEntries = getSlotEntries(slots);

    return slotEntries.map(([start, target]) => ({
      start: toStartOfDay(dayName, today, Duration.fromISOTime(start), now)
        .plus(Duration.fromISOTime(start))
        .toJSDate(),
      targetTemperature: target,
    }));
  });
  const futureSlotsSorted = [...futureSlots].sort(byStart);

  const currentSlot = futureSlotsSorted[futureSlotsSorted.length - 1];
  return [
    {
      start: DateTime.fromJSDate(currentSlot.start)
        .minus({ weeks: 1 })
        .toJSDate(),
      targetTemperature: currentSlot.targetTemperature,
    },
    ...futureSlotsSorted,
  ];
};
