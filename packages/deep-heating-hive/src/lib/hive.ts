import { combineLatest, from, Observable, timer } from 'rxjs';
import {
  getProducts,
  HeatingProductResponse,
  HiveApiAccess,
  login,
  ProductResponse,
  TrvControlProductResponse,
} from './hive-api';
import {
  filter,
  map,
  mergeAll,
  shareReplay,
  switchMap,
  throttleTime,
} from 'rxjs/operators';
import {
  TemperatureReading,
  TrvModeValue,
  WeekHeatingSchedule,
} from '@home-automation/deep-heating-types';

const refreshIntervalSeconds = 60 * 1000;
const tokenRefreshIntervalSeconds = 55 * 60 * 1000;

export function getHiveApiAccess(): Observable<HiveApiAccess> {
  return timer(0, tokenRefreshIntervalSeconds).pipe(
    switchMap(login),
    shareReplay(1)
  );
}

export function isTrvControlProduct(
  input: ProductResponse
): input is TrvControlProductResponse {
  return input.type === 'trvcontrol';
}

export function isHeatingProduct(
  input: ProductResponse
): input is HeatingProductResponse {
  return input.type === 'heating';
}

export function isProducts(
  input: ProductResponse[] | null
): input is ProductResponse[] {
  return input !== null;
}

export function getHiveProductUpdates(
  hiveApiAccess: Observable<HiveApiAccess>
): Observable<ProductResponse> {
  return combineLatest([timer(0, refreshIntervalSeconds), hiveApiAccess]).pipe(
    throttleTime(refreshIntervalSeconds),
    map(([, apiAccess]) => apiAccess),
    switchMap((apiAccess) =>
      from(getProducts(apiAccess)).pipe(filter(isProducts))
    ),
    mergeAll(),
    shareReplay(1)
  );
}

export interface TrvUpdate {
  state: {
    temperature: TemperatureReading;
    target: number;
    mode: TrvModeValue;
    isHeating: boolean;
    schedule: WeekHeatingSchedule;
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
    schedule: WeekHeatingSchedule;
  };
  heatingId: string;
  name: string;
}

export interface RoomHiveHeatingSchedule {
  roomName: string;
  schedule: WeekHeatingSchedule;
}
