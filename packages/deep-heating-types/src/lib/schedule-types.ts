import { Schema } from '@effect/schema';
import { ClimateEntityId } from './entities';
import { Temperature } from './temperature';

const Day = Schema.literal(
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday'
);

const TimeOfDay = Schema.string;
export type TimeOfDay = Schema.Schema.To<typeof TimeOfDay>;

export const ScheduleSlot = Schema.tuple(TimeOfDay, Temperature);
export type ScheduleSlot = Schema.Schema.To<typeof ScheduleSlot>;

export const DaySchedule = Schema.record(TimeOfDay, Temperature);
export type DaySchedule = Schema.Schema.To<typeof DaySchedule>;

export const WeekSchedule = Schema.record(Day, DaySchedule);
export type WeekSchedule = Schema.Schema.To<typeof WeekSchedule>;

export const TrvWeekHeatingSchedule = Schema.struct({
  climateEntityId: ClimateEntityId,
  schedule: WeekSchedule,
});
export type TrvWeekHeatingSchedule = Schema.Schema.To<
  typeof TrvWeekHeatingSchedule
>;

export const RoomWeekHeatingSchedule = Schema.struct({
  roomName: Schema.string,
  schedule: WeekSchedule,
});
export type RoomWeekHeatingSchedule = Schema.Schema.To<
  typeof RoomWeekHeatingSchedule
>;
