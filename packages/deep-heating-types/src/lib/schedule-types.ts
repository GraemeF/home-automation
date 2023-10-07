import { Schema } from '@effect/schema';
import { Temperature } from './deep-heating-types';

export interface HeatingScheduleSlot {
  value: {
    heat?: number;
    target?: number;
  };
  start: number;
}

export type DayHeatingSchedule = HeatingScheduleSlot[];

export interface WeekHeatingSchedule {
  monday: DayHeatingSchedule;
  tuesday: DayHeatingSchedule;
  wednesday: DayHeatingSchedule;
  thursday: DayHeatingSchedule;
  friday: DayHeatingSchedule;
  saturday: DayHeatingSchedule;
  sunday: DayHeatingSchedule;
}

export interface TrvWeekHeatingSchedule {
  trvId: string;
  schedule: WeekHeatingSchedule;
}

export interface RoomWeekHeatingSchedule {
  roomName: string;
  schedule: WeekHeatingSchedule;
}

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

export const SimpleDaySchedule = Schema.record(TimeOfDay, Temperature);
export type SimpleDaySchedule = Schema.Schema.To<typeof SimpleDaySchedule>;

export const SimpleWeekSchedule = Schema.record(Day, SimpleDaySchedule);
export type SimpleWeekSchedule = Schema.Schema.To<typeof SimpleWeekSchedule>;
