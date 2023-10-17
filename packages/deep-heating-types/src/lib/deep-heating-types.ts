import { Schema } from '@effect/schema';
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

const HeatingScheduleEntry = Schema.struct({
  start: Schema.Date,
  targetTemperature: Temperature,
});
export type HeatingScheduleEntry = Schema.Schema.To<
  typeof HeatingScheduleEntry
>;

const HeatingSchedule = Schema.array(HeatingScheduleEntry);
export type HeatingSchedule = Schema.Schema.To<typeof HeatingSchedule>;

const RoomSchedule = Schema.struct({
  roomName: Schema.string,
  schedule: HeatingSchedule,
});
export type RoomSchedule = Schema.Schema.To<typeof RoomSchedule>;

const RoomTargetTemperature = Schema.struct({
  roomName: Schema.string,
  targetTemperature: Temperature,
});
export type RoomTargetTemperature = Schema.Schema.To<
  typeof RoomTargetTemperature
>;

export const TrvMode = Schema.struct({
  climateEntityId: ClimateEntityId,
  mode: ClimateMode,
  source: Schema.string,
});
export type TrvMode = Schema.Schema.To<typeof TrvMode>;

export const ClimateAction = Schema.struct({
  climateEntityId: ClimateEntityId,
  mode: ClimateMode,
  targetTemperature: Temperature,
});
export type ClimateAction = Schema.Schema.To<typeof ClimateAction>;

const RoomTrvModes = Schema.struct({
  roomName: Schema.string,
  trvModes: Schema.array(TrvMode),
});
export type RoomTrvModes = Schema.Schema.To<typeof RoomTrvModes>;

const RoomTrvStatuses = Schema.struct({
  roomName: Schema.string,
  trvStatuses: Schema.array(ClimateEntityStatus),
});
export type RoomTrvStatuses = Schema.Schema.To<typeof RoomTrvStatuses>;

const RoomStatus = Schema.struct({
  roomName: Schema.string,
  isHeating: Schema.boolean,
});
export type RoomStatus = Schema.Schema.To<typeof RoomStatus>;

export const HouseModeValue = Schema.literal('Auto', 'Sleeping');
export type HouseModeValue = Schema.Schema.To<typeof HouseModeValue>;

export const RoomModeValue = Schema.literal('Off', 'Auto', 'Sleeping');
export type RoomModeValue = Schema.Schema.To<typeof RoomModeValue>;

const RoomMode = Schema.struct({
  roomName: Schema.string,
  mode: RoomModeValue,
});
export type RoomMode = Schema.Schema.To<typeof RoomMode>;

const RoomTrvTemperatures = Schema.struct({
  roomName: Schema.string,
  trvTemperatures: Schema.array(ClimateTemperatureReading),
});
export type RoomTrvTemperatures = Schema.Schema.To<typeof RoomTrvTemperatures>;

const RadiatorState = Schema.struct({
  isHeating: Schema.option(Schema.boolean),
  name: Schema.string,
  temperature: Schema.option(TemperatureReading),
  targetTemperature: Schema.option(TemperatureReading),
  desiredTargetTemperature: Schema.option(TemperatureReading),
});
export type RadiatorState = Schema.Schema.To<typeof RadiatorState>;

export const RoomState = Schema.struct({
  name: Schema.string,
  temperature: Schema.option(TemperatureReading),
  targetTemperature: Schema.option(Temperature),
  radiators: Schema.array(RadiatorState),
  mode: Schema.option(RoomModeValue),
  isHeating: Schema.option(Schema.boolean),
  adjustment: Schema.number,
});
export type RoomState = Schema.Schema.To<typeof RoomState>;

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

export const DeepHeatingState = Schema.struct({
  rooms: Schema.array(RoomState),
  isHeating: Schema.option(Schema.boolean),
});
export type DeepHeatingState = Schema.Schema.To<typeof DeepHeatingState>;

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
