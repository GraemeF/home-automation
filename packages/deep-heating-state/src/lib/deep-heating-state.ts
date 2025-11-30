import { DeepHeating } from '@home-automation/deep-heating-rx';
import {
  DeepHeatingState,
  RadiatorState,
  RoomDefinition,
  RoomState,
} from '@home-automation/deep-heating-types';
import { Array, Option, pipe } from 'effect';
import { Observable } from 'rxjs';
import { multiScan } from 'rxjs-multi-scan';
import { filter, mergeAll, mergeMap, startWith } from 'rxjs/operators';

export const addOrReplace = <T>(
  array: ReadonlyArray<T>,
  element: T,
  idKey: keyof T,
): ReadonlyArray<T> =>
  pipe(
    array,
    Array.findFirstIndex((f) => f[idKey] === element[idKey]),
    Option.match({
      onSome: (index) => pipe(array, Array.replace(index, element)),
      onNone: () => pipe(array, Array.append(element)),
    }),
  );

function maintainTrvState(
  deepHeating: DeepHeating,
  trvId: string,
): Observable<RadiatorState> {
  const initialState: RadiatorState = {
    name: trvId,
    desiredTargetTemperature: Option.none(),
    isHeating: Option.none(),
    targetTemperature: Option.none(),
    temperature: Option.none(),
  };
  return multiScan(
    deepHeating.trvTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
    ),
    (state, update) => ({
      ...state,
      temperature: Option.some(update.temperatureReading),
    }),

    deepHeating.trvTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
    ),
    (state, update) => ({
      ...state,
      targetTemperature: Option.some({
        temperature: update.targetTemperature,
        time: new Date(),
      }),
    }),

    deepHeating.trvStatuses$.pipe(filter((x) => x.climateEntityId === trvId)),
    (state, update) => ({
      ...state,
      isHeating: Option.some(update.isHeating),
    }),

    deepHeating.trvDesiredTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
    ),
    (state, desired) => ({
      ...state,
      desiredTargetTemperature: Option.some({
        temperature: desired.targetTemperature,
        time: new Date(),
      }),
    }),

    initialState,
  ).pipe(startWith<RadiatorState>(initialState));
}

function maintainRoomState(
  deepHeating: DeepHeating,
  room: RoomDefinition,
): Observable<RoomState> {
  const initialRoomState: RoomState = {
    radiators: Array.empty<RadiatorState>(),
    name: room.name,
    adjustment: 0,
    isHeating: Option.none(),
    mode: Option.none(),
    targetTemperature: Option.none(),
    temperature: Option.none(),
  };
  return multiScan(
    deepHeating.roomTemperatures$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      temperature: Option.some(update.temperatureReading),
    }),

    deepHeating.roomTargetTemperatures$.pipe(
      filter((x) => x.roomName === room.name),
    ),
    (state, update) => ({
      ...state,
      targetTemperature: Option.some(update.targetTemperature),
    }),

    deepHeating.roomModes$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      mode: Option.some(update.mode),
    }),

    deepHeating.roomStatuses$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      isHeating: Option.some(update.isHeating),
    }),

    deepHeating.roomAdjustments$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      adjustment: update.adjustment,
    }),

    deepHeating.roomTrvs$.pipe(
      filter((x) => x.roomName === room.name),
      mergeMap((x) =>
        x.climateEntityIds.map((y) => maintainTrvState(deepHeating, y)),
      ),
      mergeAll(),
    ),
    (state, _update) => ({
      ...state,
      radiators: addOrReplace(state.radiators, _update, 'name'),
    }),

    initialRoomState,
  ).pipe(startWith<RoomState>(initialRoomState));
}

const emptyState: DeepHeatingState = {
  rooms: Array.empty<RoomState>(),
  isHeating: Option.none(),
};

export function maintainState(
  deepHeating: DeepHeating,
): Observable<DeepHeatingState> {
  return multiScan(
    deepHeating.rooms$.pipe(
      mergeMap((x) =>
        x.pipe(
          mergeMap((roomDefinition) =>
            maintainRoomState(deepHeating, roomDefinition),
          ),
        ),
      ),
    ),
    (state, roomState) => ({
      ...state,
      rooms: addOrReplace(state.rooms, roomState, 'name'),
    }),

    deepHeating.heatingStatuses$,
    (state, heatingStatus) => ({
      ...state,
      isHeating: Option.some(heatingStatus.isHeating),
    }),

    emptyState,
  );
}
