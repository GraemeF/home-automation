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
