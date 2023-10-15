import { Schema } from '@effect/schema';
import { DateTime } from 'luxon';
import { ClimateEntityId, EventEntityId, SensorEntityId } from './entities';
import { ClimateMode } from './home-assistant';
import { WeekSchedule } from './schedule-types';
import { Temperature } from './temperature';

export const ClimateTargetTemperature = Schema.struct({
  climateEntityId: ClimateEntityId,
  targetTemperature: Temperature,
});
export type ClimateTargetTemperature = Schema.Schema.To<
  typeof ClimateTargetTemperature
>;

export const RoomClimateTargetTemperatures = Schema.struct({
  roomName: Schema.string,
  climateTargetTemperatures: Schema.array(ClimateTargetTemperature),
});
export type RoomClimateTargetTemperatures = Schema.Schema.To<
  typeof RoomClimateTargetTemperatures
>;

const TemperatureReading = Schema.struct({
  temperature: Temperature,
  time: Schema.Date,
});
export type TemperatureReading = Schema.Schema.To<typeof TemperatureReading>;

const ClimateTemperatureReading = Schema.struct({
  climateEntityId: ClimateEntityId,
  temperatureReading: TemperatureReading,
});
export type ClimateTemperatureReading = Schema.Schema.To<
  typeof ClimateTemperatureReading
>;

const RoomDefinition = Schema.struct({
  name: Schema.string,
  temperatureSensorEntityId: Schema.optionFromNullable(SensorEntityId),
  climateEntityIds: Schema.array(ClimateEntityId),
  schedule: Schema.optionFromNullable(WeekSchedule),
});
export type RoomDefinition = Schema.Schema.To<typeof RoomDefinition>;

const RoomClimateEntities = Schema.struct({
  roomName: Schema.string,
  climateEntityIds: Schema.array(ClimateEntityId),
});
export type RoomClimateEntities = Schema.Schema.To<typeof RoomClimateEntities>;

const ClimateEntityStatus = Schema.struct({
  climateEntityId: ClimateEntityId,
  isHeating: Schema.boolean,
});
export type ClimateEntityStatus = Schema.Schema.To<typeof ClimateEntityStatus>;

const HeatingStatus = Schema.struct({
  heatingId: ClimateEntityId,
  isHeating: Schema.boolean,
  source: Schema.string,
});
export type HeatingStatus = Schema.Schema.To<typeof HeatingStatus>;

export interface HeatingScheduleEntry {
  start: DateTime;
  targetTemperature: Temperature;
}

export type HeatingSchedule = HeatingScheduleEntry[];

export interface RoomSchedule {
  roomName: string;
  schedule: HeatingSchedule;
}

export interface RoomTargetTemperature {
  roomName: string;
  targetTemperature: Temperature;
}

export const TrvMode = Schema.struct({
  climateEntityId: ClimateEntityId,
  mode: ClimateMode,
  source: Schema.string,
});
export type TrvMode = Schema.Schema.To<typeof TrvMode>;

export const TrvAction = Schema.struct({
  climateEntityId: ClimateEntityId,
  mode: ClimateMode,
  targetTemperature: Temperature,
});
export type TrvAction = Schema.Schema.To<typeof TrvAction>;

export interface RoomTrvModes {
  roomName: string;
  trvModes: TrvMode[];
}

export interface RoomTrvStatuses {
  roomName: string;
  trvStatuses: ClimateEntityStatus[];
}

export interface RoomStatus {
  roomName: string;
  isHeating: boolean;
}

export type HouseModeValue = 'Auto' | 'Sleeping';
export type RoomModeValue = 'Off' | 'Auto' | 'Sleeping';

export interface RoomMode {
  roomName: string;
  mode: RoomModeValue;
}

export interface RoomTrvTemperatures {
  roomName: string;
  trvTemperatures: ClimateTemperatureReading[];
}

export interface RadiatorState {
  isHeating?: boolean;
  name?: string;
  temperature?: TemperatureReading;
  targetTemperature?: TemperatureReading;
  desiredTargetTemperature?: TemperatureReading;
}

export interface RoomState {
  name: string;
  temperature?: TemperatureReading;
  targetTemperature?: Temperature;
  radiators: RadiatorState[];
  mode?: RoomModeValue;
  isHeating?: boolean;
  adjustment: number;
}

export interface RoomTemperature {
  roomName: string;
  temperatureReading: TemperatureReading;
}

const RoomSensors = Schema.struct({
  roomName: Schema.string,
  temperatureSensorIds: Schema.array(SensorEntityId),
});
export type RoomSensors = Schema.Schema.To<typeof RoomSensors>;

export const RoomDecisionPoint = Schema.struct({
  roomName: Schema.string,
  targetTemperature: Temperature,
  temperature: Temperature,
  trvTargetTemperatures: Schema.array(ClimateTargetTemperature),
  trvTemperatures: Schema.array(ClimateTemperatureReading),
  trvModes: Schema.array(TrvMode),
});
export type RoomDecisionPoint = Schema.Schema.To<typeof RoomDecisionPoint>;

export interface RoomAdjustment {
  roomName: string;
  adjustment: number;
}

export interface DeepHeatingState {
  rooms: RoomState[];
  isHeating?: boolean;
}

export const Home = Schema.struct({
  rooms: Schema.array(RoomDefinition),
  sleepSwitchId: EventEntityId,
  heatingId: ClimateEntityId,
});
export type Home = Schema.Schema.To<typeof Home>;

export interface TrvScheduledTargetTemperature {
  climateEntityId: ClimateEntityId;
  scheduledTargetTemperature: Temperature;
}

export const UpdateSource = Schema.literal('Device', 'Synthesised');
export type UpdateSource = Schema.Schema.To<typeof UpdateSource>;

export const TrvControlState = Schema.struct({
  climateEntityId: ClimateEntityId,
  targetTemperature: Temperature,
  mode: ClimateMode,
  source: UpdateSource,
});
export type TrvControlState = Schema.Schema.To<typeof TrvControlState>;

export const TrvUpdate = Schema.struct({
  state: Schema.struct({
    temperature: TemperatureReading,
    target: Temperature,
    mode: ClimateMode,
    isHeating: Schema.boolean,
    schedule: WeekSchedule,
  }),
  climateEntityId: ClimateEntityId,
  deviceType: Schema.string,
  name: Schema.string,
});
export type TrvUpdate = Schema.Schema.To<typeof TrvUpdate>;

export const HeatingUpdate = Schema.struct({
  state: Schema.struct({
    temperature: TemperatureReading,
    target: Temperature,
    mode: Schema.string,
    isHeating: Schema.boolean,
  }),
  heatingId: ClimateEntityId,
  name: Schema.string,
});
export type HeatingUpdate = Schema.Schema.To<typeof HeatingUpdate>;

export const HeatingAction = Schema.struct({
  heatingId: ClimateEntityId,
  mode: ClimateMode,
  targetTemperature: Temperature,
});
export type HeatingAction = Schema.Schema.To<typeof HeatingAction>;
