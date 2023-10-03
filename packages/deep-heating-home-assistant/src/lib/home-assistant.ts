import { from, Observable, timer } from 'rxjs';
import { getClimateEntities } from './home-assistant-api';
import { shareReplay, switchMap, throttleTime } from 'rxjs/operators';
import {
  TemperatureReading,
  TrvModeValue,
} from '@home-automation/deep-heating-types';
import { ClimateEntity } from './schema';
import { Effect, pipe } from 'effect';

const refreshIntervalSeconds = 60 * 1000;

export const getClimateEntityUpdates = (): Observable<ClimateEntity> =>
  timer(0, refreshIntervalSeconds).pipe(
    throttleTime(refreshIntervalSeconds),
    switchMap(() => from(pipe(getClimateEntities, Effect.runSync))),
    shareReplay(1)
  );

export interface HomeAssistantHeatingScheduleSlot {
  value: {
    heat?: number;
    target?: number;
  };
  start: number;
}

export type HomeAssistantDayHeatingSchedule =
  HomeAssistantHeatingScheduleSlot[];

export interface HomeAssistantHeatingSchedule {
  monday: HomeAssistantDayHeatingSchedule;
  tuesday: HomeAssistantDayHeatingSchedule;
  wednesday: HomeAssistantDayHeatingSchedule;
  thursday: HomeAssistantDayHeatingSchedule;
  friday: HomeAssistantDayHeatingSchedule;
  saturday: HomeAssistantDayHeatingSchedule;
  sunday: HomeAssistantDayHeatingSchedule;
}

export interface TrvUpdate {
  state: {
    temperature: TemperatureReading;
    target: number;
    mode: TrvModeValue;
    isHeating: boolean;
    schedule: HomeAssistantHeatingSchedule;
  };
  trvId: string;
  deviceType: string;
  name: string;
}

export interface HeatingUpdate {
  state: {
    temperature: TemperatureReading;
    target: number;
    mode: string;
    isHeating: boolean;
    schedule: HomeAssistantHeatingSchedule;
  };
  heatingId: string;
  name: string;
}

export interface TrvControlState {
  trvId: string;
  targetTemperature: number;
  mode: TrvModeValue;
  source: HomeAssistantUpdateSource;
}

export type HomeAssistantUpdateSource = 'HomeAssistant' | 'Synthesised';

export interface RoomHomeAssistantHeatingSchedule {
  roomName: string;
  schedule: HomeAssistantHeatingSchedule;
}
