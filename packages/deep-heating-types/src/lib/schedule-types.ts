import { Schema } from 'effect';
import { ClimateEntityId } from './entities';
import { Temperature } from './temperature';

const Day = Schema.Literal(
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
);

const TimeOfDay = Schema.String;
export type TimeOfDay = typeof TimeOfDay.Type;

export const ScheduleSlot = Schema.Tuple(TimeOfDay, Temperature);
export type ScheduleSlot = typeof ScheduleSlot.Type;

export const DaySchedule = Schema.Record({
  key: TimeOfDay,
  value: Temperature,
});
export type DaySchedule = typeof DaySchedule.Type;

export const WeekSchedule = Schema.Record({ key: Day, value: DaySchedule });
export type WeekSchedule = typeof WeekSchedule.Type;

export const TrvWeekHeatingSchedule = Schema.Struct({
  climateEntityId: ClimateEntityId,
  schedule: WeekSchedule,
});
export type TrvWeekHeatingSchedule = typeof TrvWeekHeatingSchedule.Type;

export const RoomWeekHeatingSchedule = Schema.Struct({
  roomName: Schema.String,
  schedule: WeekSchedule,
});
export type RoomWeekHeatingSchedule = typeof RoomWeekHeatingSchedule.Type;
