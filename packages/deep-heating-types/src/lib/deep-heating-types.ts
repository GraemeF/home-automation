import { Schema } from 'effect';
import { ClimateEntityId, GoodnightEntityId, SensorEntityId } from './entities';
import { ClimateMode, OperationalClimateMode } from './home-assistant';
import { WeekSchedule } from './schedule-types';
import { Temperature } from './temperature';

export const ClimateTargetTemperature = Schema.Struct({
  climateEntityId: ClimateEntityId,
  targetTemperature: Temperature,
});
export type ClimateTargetTemperature = typeof ClimateTargetTemperature.Type;

export const RoomClimateTargetTemperatures = Schema.Struct({
  roomName: Schema.String,
  climateTargetTemperatures: Schema.Array(ClimateTargetTemperature),
});
export type RoomClimateTargetTemperatures =
  typeof RoomClimateTargetTemperatures.Type;

const TemperatureReading = Schema.Struct({
  temperature: Temperature,
  time: Schema.Date,
});
export type TemperatureReading = typeof TemperatureReading.Type;

const ClimateTemperatureReading = Schema.Struct({
  climateEntityId: ClimateEntityId,
  temperatureReading: TemperatureReading,
});
export type ClimateTemperatureReading = typeof ClimateTemperatureReading.Type;

const RoomDefinition = Schema.Struct({
  name: Schema.String,
  temperatureSensorEntityId: Schema.OptionFromNullOr(SensorEntityId),
  climateEntityIds: Schema.Array(ClimateEntityId),
  schedule: Schema.OptionFromNullOr(WeekSchedule),
});
export type RoomDefinition = typeof RoomDefinition.Type;

const RoomClimateEntities = Schema.Struct({
  roomName: Schema.String,
  climateEntityIds: Schema.Array(ClimateEntityId),
});
export type RoomClimateEntities = typeof RoomClimateEntities.Type;

const ClimateEntityStatus = Schema.Struct({
  climateEntityId: ClimateEntityId,
  isHeating: Schema.Boolean,
});
export type ClimateEntityStatus = typeof ClimateEntityStatus.Type;

const HeatingStatus = Schema.Struct({
  heatingId: ClimateEntityId,
  isHeating: Schema.Boolean,
  source: Schema.String,
});
export type HeatingStatus = typeof HeatingStatus.Type;

const HeatingScheduleEntry = Schema.Struct({
  start: Schema.Date,
  targetTemperature: Temperature,
});
export type HeatingScheduleEntry = typeof HeatingScheduleEntry.Type;

const HeatingSchedule = Schema.Array(HeatingScheduleEntry);
export type HeatingSchedule = typeof HeatingSchedule.Type;

const RoomSchedule = Schema.Struct({
  roomName: Schema.String,
  schedule: HeatingSchedule,
});
export type RoomSchedule = typeof RoomSchedule.Type;

const RoomTargetTemperature = Schema.Struct({
  roomName: Schema.String,
  targetTemperature: Temperature,
});
export type RoomTargetTemperature = typeof RoomTargetTemperature.Type;

export const TrvMode = Schema.Struct({
  climateEntityId: ClimateEntityId,
  mode: ClimateMode,
  source: Schema.String,
});
export type TrvMode = typeof TrvMode.Type;

export const ClimateAction = Schema.Struct({
  climateEntityId: ClimateEntityId,
  mode: OperationalClimateMode,
  targetTemperature: Temperature,
});
export type ClimateAction = typeof ClimateAction.Type;

const RoomTrvModes = Schema.Struct({
  roomName: Schema.String,
  trvModes: Schema.Array(TrvMode),
});
export type RoomTrvModes = typeof RoomTrvModes.Type;

const RoomTrvStatuses = Schema.Struct({
  roomName: Schema.String,
  trvStatuses: Schema.Array(ClimateEntityStatus),
});
export type RoomTrvStatuses = typeof RoomTrvStatuses.Type;

const RoomStatus = Schema.Struct({
  roomName: Schema.String,
  isHeating: Schema.Boolean,
});
export type RoomStatus = typeof RoomStatus.Type;

export const HouseModeValue = Schema.Literal('Auto', 'Sleeping');
export type HouseModeValue = typeof HouseModeValue.Type;

export const RoomModeValue = Schema.Literal('Off', 'Auto', 'Sleeping');
export type RoomModeValue = typeof RoomModeValue.Type;

const RoomMode = Schema.Struct({
  roomName: Schema.String,
  mode: RoomModeValue,
});
export type RoomMode = typeof RoomMode.Type;

const RoomTrvTemperatures = Schema.Struct({
  roomName: Schema.String,
  trvTemperatures: Schema.Array(ClimateTemperatureReading),
});
export type RoomTrvTemperatures = typeof RoomTrvTemperatures.Type;

const RadiatorState = Schema.Struct({
  isHeating: Schema.Option(Schema.Boolean),
  name: Schema.String,
  temperature: Schema.OptionFromNullOr(TemperatureReading),
  targetTemperature: Schema.Option(TemperatureReading),
  desiredTargetTemperature: Schema.Option(TemperatureReading),
});
export type RadiatorState = typeof RadiatorState.Type;

export const RoomState = Schema.Struct({
  name: Schema.String,
  temperature: Schema.Option(TemperatureReading),
  targetTemperature: Schema.Option(Temperature),
  radiators: Schema.Array(RadiatorState),
  mode: Schema.Option(RoomModeValue),
  isHeating: Schema.Option(Schema.Boolean),
  adjustment: Schema.Number,
});
export type RoomState = typeof RoomState.Type;

export interface RoomTemperature {
  readonly roomName: string;
  readonly temperatureReading: TemperatureReading;
}

const RoomSensors = Schema.Struct({
  roomName: Schema.String,
  temperatureSensorIds: Schema.Array(SensorEntityId),
});
export type RoomSensors = typeof RoomSensors.Type;

export const RoomDecisionPoint = Schema.Struct({
  roomName: Schema.String,
  targetTemperature: Temperature,
  temperature: Temperature,
  trvTargetTemperatures: Schema.Array(ClimateTargetTemperature),
  trvTemperatures: Schema.Array(ClimateTemperatureReading),
  trvModes: Schema.Array(TrvMode),
});
export type RoomDecisionPoint = typeof RoomDecisionPoint.Type;

export interface RoomAdjustment {
  readonly roomName: string;
  readonly adjustment: number;
}

export const DeepHeatingState = Schema.Struct({
  rooms: Schema.Array(RoomState),
  isHeating: Schema.Option(Schema.Boolean),
});
export type DeepHeatingState = typeof DeepHeatingState.Type;

export const Home = Schema.Struct({
  rooms: Schema.Array(RoomDefinition),
  sleepSwitchId: GoodnightEntityId,
  heatingId: ClimateEntityId,
});
export type Home = typeof Home.Type;

export interface TrvScheduledTargetTemperature {
  readonly climateEntityId: ClimateEntityId;
  readonly scheduledTargetTemperature: Temperature;
}

export const UpdateSource = Schema.Literal('Device', 'Synthesised');
export type UpdateSource = typeof UpdateSource.Type;

export const TrvControlState = Schema.Struct({
  climateEntityId: ClimateEntityId,
  targetTemperature: Temperature,
  mode: OperationalClimateMode,
  source: UpdateSource,
});
export type TrvControlState = typeof TrvControlState.Type;

export const TrvUpdate = Schema.Struct({
  state: Schema.Struct({
    temperature: TemperatureReading,
    target: Temperature,
    mode: OperationalClimateMode,
    isHeating: Schema.Boolean,
    schedule: WeekSchedule,
  }),
  climateEntityId: ClimateEntityId,
  deviceType: Schema.String,
  name: Schema.String,
});
export type TrvUpdate = typeof TrvUpdate.Type;

export const HeatingUpdate = Schema.Struct({
  state: Schema.Struct({
    temperature: TemperatureReading,
    target: Temperature,
    mode: OperationalClimateMode,
    isHeating: Schema.Boolean,
  }),
  heatingId: ClimateEntityId,
  name: Schema.String,
});
export type HeatingUpdate = typeof HeatingUpdate.Type;
