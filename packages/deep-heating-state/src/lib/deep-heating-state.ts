import { DeepHeating } from '@home-automation/deep-heating-rx';
import {
  DeepHeatingState,
  RadiatorState,
  RoomDefinition,
  RoomState,
} from '@home-automation/deep-heating-types';
import { Array, Option, pipe } from 'effect';
import { merge, Observable } from 'rxjs';
import {
  filter,
  map,
  mergeAll,
  mergeMap,
  scan,
  startWith,
} from 'rxjs/operators';

const replaceAtIndex =
  <T>(array: ReadonlyArray<T>, element: T) =>
  (index: number): ReadonlyArray<T> =>
    pipe(array, Array.replace(index, element));

const appendToArray =
  <T>(array: ReadonlyArray<T>, element: T) =>
  (): ReadonlyArray<T> =>
    pipe(array, Array.append(element));

export const addOrReplace = <T>(
  array: ReadonlyArray<T>,
  element: T,
  idKey: keyof T,
): ReadonlyArray<T> =>
  pipe(
    array,
    Array.findFirstIndex((f) => f[idKey] === element[idKey]),
    Option.match({
      onSome: replaceAtIndex(array, element),
      onNone: appendToArray(array, element),
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
  return merge(
    deepHeating.trvTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
      map(
        (update) => (state: RadiatorState) =>
          ({
            ...state,
            temperature: Option.some(update.temperatureReading),
          }) as const,
      ),
    ),
    deepHeating.trvTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
      map(
        (update) => (state: RadiatorState) =>
          ({
            ...state,
            targetTemperature: Option.some({
              temperature: update.targetTemperature,
              time: new Date(),
            }),
          }) as const,
      ),
    ),
    deepHeating.trvStatuses$.pipe(
      filter((x) => x.climateEntityId === trvId),
      map(
        (update) => (state: RadiatorState) =>
          ({
            ...state,
            isHeating: Option.some(update.isHeating),
          }) as const,
      ),
    ),
    deepHeating.trvDesiredTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId),
      map(
        (desired) => (state: RadiatorState) =>
          ({
            ...state,
            desiredTargetTemperature: Option.some({
              temperature: desired.targetTemperature,
              time: new Date(),
            }),
          }) as const,
      ),
    ),
  ).pipe(
    scan((state, reducer) => reducer(state), initialState),
    startWith(initialState),
  );
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
  return merge(
    deepHeating.roomTemperatures$.pipe(
      filter((x) => x.roomName === room.name),
      map(
        (update) => (state: RoomState) =>
          ({
            ...state,
            temperature: Option.some(update.temperatureReading),
          }) as const,
      ),
    ),
    deepHeating.roomTargetTemperatures$.pipe(
      filter((x) => x.roomName === room.name),
      map(
        (update) => (state: RoomState) =>
          ({
            ...state,
            targetTemperature: Option.some(update.targetTemperature),
          }) as const,
      ),
    ),
    deepHeating.roomModes$.pipe(
      filter((x) => x.roomName === room.name),
      map(
        (update) => (state: RoomState) =>
          ({
            ...state,
            mode: Option.some(update.mode),
          }) as const,
      ),
    ),
    deepHeating.roomStatuses$.pipe(
      filter((x) => x.roomName === room.name),
      map(
        (update) => (state: RoomState) =>
          ({
            ...state,
            isHeating: Option.some(update.isHeating),
          }) as const,
      ),
    ),
    deepHeating.roomAdjustments$.pipe(
      filter((x) => x.roomName === room.name),
      map(
        (update) => (state: RoomState) =>
          ({
            ...state,
            adjustment: update.adjustment,
          }) as const,
      ),
    ),
    deepHeating.roomTrvs$.pipe(
      filter((x) => x.roomName === room.name),
      mergeMap((x) =>
        x.climateEntityIds.map((y) => maintainTrvState(deepHeating, y)),
      ),
      mergeAll(),
      map(
        (radiatorState) => (state: RoomState) =>
          ({
            ...state,
            radiators: addOrReplace(state.radiators, radiatorState, 'name'),
          }) as const,
      ),
    ),
  ).pipe(
    scan((state, reducer) => reducer(state), initialRoomState),
    startWith(initialRoomState),
  );
}

const emptyState: DeepHeatingState = {
  rooms: Array.empty<RoomState>(),
  isHeating: Option.none(),
};

export function maintainState(
  deepHeating: DeepHeating,
): Observable<DeepHeatingState> {
  return merge(
    deepHeating.rooms$.pipe(
      mergeMap((x) =>
        x.pipe(
          mergeMap((roomDefinition) =>
            maintainRoomState(deepHeating, roomDefinition),
          ),
        ),
      ),
      map(
        (roomState) => (state: DeepHeatingState) =>
          ({
            ...state,
            rooms: addOrReplace(state.rooms, roomState, 'name'),
          }) as const,
      ),
    ),
    deepHeating.heatingStatuses$.pipe(
      map(
        (heatingStatus) => (state: DeepHeatingState) =>
          ({
            ...state,
            isHeating: Option.some(heatingStatus.isHeating),
          }) as const,
      ),
    ),
  ).pipe(
    scan((state, reducer) => reducer(state), emptyState),
    startWith(emptyState),
  );
}
