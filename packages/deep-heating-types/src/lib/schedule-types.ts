import { Schema } from '@effect/schema';
import { ClimateEntityId } from './entities';
import { Temperature } from './temperature';

export const HeatingScheduleSlot = Schema.struct({
  value: Schema.struct({
    target: Temperature,
  }),
  start: Schema.number,
});
export type HeatingScheduleSlot = Schema.Schema.To<typeof HeatingScheduleSlot>;

export const DayHeatingSchedule = Schema.array(HeatingScheduleSlot);
export type DayHeatingSchedule = Schema.Schema.To<typeof DayHeatingSchedule>;

export const WeekHeatingSchedule = Schema.struct({
  monday: DayHeatingSchedule,
  tuesday: DayHeatingSchedule,
  wednesday: DayHeatingSchedule,
  thursday: DayHeatingSchedule,
  friday: DayHeatingSchedule,
  saturday: DayHeatingSchedule,
  sunday: DayHeatingSchedule,
});
export type WeekHeatingSchedule = Schema.Schema.To<typeof WeekHeatingSchedule>;

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

export const SimpleHeatingSlot = Schema.tuple(TimeOfDay, Temperature);
export type SimpleHeatingSlot = Schema.Schema.To<typeof SimpleHeatingSlot>;

export const SimpleDaySchedule = Schema.record(TimeOfDay, Temperature);
export type SimpleDaySchedule = Schema.Schema.To<typeof SimpleDaySchedule>;

export const SimpleWeekSchedule = Schema.record(Day, SimpleDaySchedule);
export type SimpleWeekSchedule = Schema.Schema.To<typeof SimpleWeekSchedule>;

export const TrvWeekHeatingSchedule = Schema.struct({
  climateEntityId: ClimateEntityId,
  schedule: SimpleWeekSchedule,
});
export type TrvWeekHeatingSchedule = Schema.Schema.To<
  typeof TrvWeekHeatingSchedule
>;

export const RoomWeekHeatingSchedule = Schema.struct({
  roomName: Schema.string,
  schedule: SimpleWeekSchedule,
});
export type RoomWeekHeatingSchedule = Schema.Schema.To<
  typeof RoomWeekHeatingSchedule
>;
