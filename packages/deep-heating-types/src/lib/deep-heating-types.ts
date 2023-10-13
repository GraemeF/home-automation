import { Schema } from '@effect/schema';
import { DateTime } from 'luxon';
import { ClimateEntityId, EventEntityId, SensorEntityId } from './entities';
import { SimpleWeekSchedule, WeekHeatingSchedule } from './schedule-types';
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
  schedule: Schema.optionFromNullable(SimpleWeekSchedule),
});
export type RoomDefinition = Schema.Schema.To<typeof RoomDefinition>;

const RoomClimateEntities = Schema.struct({
  roomName: Schema.string,
  climateEntityIds: Schema.array(ClimateEntityId),
});
export type RoomClimateEntities = Schema.Schema.To<typeof RoomClimateEntities>;

export interface TrvStatus {
  climateEntityId: ClimateEntityId;
  isHeating: boolean;
}

export interface HeatingStatus {
  heatingId: string;
  isHeating: boolean;
  source: string;
}

export interface SensorState {
  lastupdated: string;
}

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

export const TrvModeValue = Schema.literal('OFF', 'MANUAL', 'SCHEDULE');
export type TrvModeValue = Schema.Schema.To<typeof TrvModeValue>;

export const TrvMode = Schema.struct({
  climateEntityId: ClimateEntityId,
  mode: TrvModeValue,
  source: Schema.string,
});
export type TrvMode = Schema.Schema.To<typeof TrvMode>;

export interface TrvAction {
  climateEntityId: ClimateEntityId;
  mode: TrvModeValue;
  targetTemperature?: Temperature;
}

export interface RoomTrvModes {
  roomName: string;
  trvModes: TrvMode[];
}

export interface RoomTrvStatuses {
  roomName: string;
  trvStatuses: TrvStatus[];
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

export interface SensorUpdate<TState extends SensorState = SensorState> {
  uniqueid: string;
  state: TState;
  type: string;
}

export interface TemperatureSensorState extends SensorState {
  temperature: Temperature;
}

export interface SwitchSensorState extends SensorState {
  buttonevent: number | null;
}

export interface TemperatureSensorUpdate extends SensorUpdate {
  state: TemperatureSensorState;
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
  mode: TrvModeValue,
  source: UpdateSource,
});
export type TrvControlState = Schema.Schema.To<typeof TrvControlState>;

export interface TrvUpdate {
  state: {
    temperature: TemperatureReading;
    target: Temperature;
    mode: TrvModeValue;
    isHeating: boolean;
    schedule: WeekHeatingSchedule;
  };
  climateEntityId: ClimateEntityId;
  deviceType: string;
  name: string;
}

export interface HeatingUpdate {
  state: {
    temperature: TemperatureReading;
    target: Temperature;
    mode: string;
    isHeating: boolean;
    schedule: WeekHeatingSchedule;
  };
  heatingId: string;
  name: string;
}
