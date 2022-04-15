import { DateTime } from 'luxon';

export interface TrvTargetTemperature {
  trvId: string;
  targetTemperature: number;
}

export interface TrvTemperature {
  trvId: string;
  temperatureReading: TemperatureReading;
}

export interface RoomDefinition {
  name: string;
  temperatureSensorId: string | null;
  trvControlIds: (string | null)[];
}

export interface TrvStatus {
  trvId: string;
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
  targetTemperature: number;
}

export type HeatingSchedule = HeatingScheduleEntry[];

export interface RoomSchedule {
  roomName: string;
  schedule: HeatingScheduleEntry[];
}

export interface RoomTargetTemperature {
  roomName: string;
  targetTemperature: number;
}

export type TrvModeValue = 'OFF' | 'MANUAL' | 'SCHEDULE';

export interface TrvMode {
  trvId: string;
  mode: TrvModeValue;
  source: string;
}

export interface TrvAction {
  trvId: string;
  mode: TrvModeValue;
  targetTemperature?: number;
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
  trvTargetTemperatures: TrvTemperature[];
}

export interface SensorUpdate<TState extends SensorState = SensorState> {
  uniqueid: string;
  state: TState;
  type: string;
}

export interface TemperatureSensorState extends SensorState {
  temperature: number;
}

export interface SwitchSensorState extends SensorState {
  buttonevent: number;
}

export interface TemperatureSensorUpdate extends SensorUpdate {
  state: TemperatureSensorState;
}

export interface ButtonEventDefinition {
  buttonevent: number;
  eventtype: string;
}

export interface ButtonDefinition {
  events: ButtonEventDefinition[];
}

export interface SwitchSensorUpdate extends SensorUpdate {
  state: SwitchSensorState;
  name: string;
  capabilities: { inputs: ButtonDefinition[] };
}

export type DegreesCelsius = number;

export interface TemperatureReading {
  temperature: DegreesCelsius;
  time: DateTime;
}

export interface RadiatorState {
  isHeating?: boolean;
  name?: string;
  temperature?: TemperatureReading;
  targetTemperature?: TemperatureReading;
}

export interface RoomState {
  name: string;
  temperature?: TemperatureReading;
  targetTemperature?: number;
  radiators: RadiatorState[];
  mode?: RoomModeValue;
  isHeating?: boolean;
  adjustment: number;
}

export interface ButtonEvent {
  switchId: string;
  switchName: string;
  buttonIndex: number;
  eventType: string;
  time: DateTime;
}

export interface RoomTemperature {
  roomName: string;
  temperatureReading: TemperatureReading;
}

export interface RoomSensors {
  roomName: string;
  temperatureSensorIds: string[];
}

export interface RoomDecisionPoint {
  roomName: string;
  targetTemperature: number;
  temperature: number;
  trvTargetTemperatures: TrvTargetTemperature[];
  trvTemperatures: TrvTemperature[];
  trvModes: TrvMode[];
}

export interface RoomAdjustment {
  roomName: string;
  adjustment: number;
}

export interface DeepHeatingState {
  rooms: RoomState[];
  isHeating?: boolean;
}
