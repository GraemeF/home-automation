import { DeepHeating } from '@home-automation/deep-heating-rx';
import {
  DeepHeatingState,
  RadiatorState,
  RoomDefinition,
  RoomState,
} from '@home-automation/deep-heating-types';
import { Observable } from 'rxjs';
import { multiScan } from 'rxjs-multi-scan';
import { filter, mergeAll, mergeMap, startWith } from 'rxjs/operators';

export const addOrReplace = function <T>(a: T[], o: T, k: keyof T): T[] {
  const fi = a.findIndex((f) => f[k] === o[k]);
  if (fi !== -1) {
    a.splice(fi, 1, o);
  } else {
    a.push(o);
  }
  return a;
};

function maintainTrvState(
  deepHeating: DeepHeating,
  trvId: string
): Observable<RadiatorState> {
  const initialState: RadiatorState = { name: trvId };
  return multiScan(
    deepHeating.trvTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId)
    ),
    (state, update) => ({
      ...state,
      temperature: update.temperatureReading,
    }),

    deepHeating.trvTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId)
    ),
    (state, update) => ({
      ...state,
      targetTemperature: {
        temperature: update.targetTemperature,
        time: new Date(),
      },
    }),

    deepHeating.trvStatuses$.pipe(filter((x) => x.climateEntityId === trvId)),
    (state, update) => ({
      ...state,
      isHeating: update.isHeating,
    }),

    deepHeating.trvDesiredTargetTemperatures$.pipe(
      filter((x) => x.climateEntityId === trvId)
    ),
    (state, desired) => ({
      ...state,
      desiredTargetTemperature: {
        temperature: desired.targetTemperature,
        time: new Date(),
      },
    }),

    initialState
  ).pipe(startWith<RadiatorState>(initialState));
}

function maintainRoomState(
  deepHeating: DeepHeating,
  room: RoomDefinition
): Observable<RoomState> {
  const initialRoomState: RoomState = {
    radiators: [],
    name: room.name,
    adjustment: 0,
  };
  return multiScan(
    deepHeating.roomTemperatures$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      temperature: update.temperatureReading,
    }),

    deepHeating.roomTargetTemperatures$.pipe(
      filter((x) => x.roomName === room.name)
    ),
    (state, update) => ({
      ...state,
      targetTemperature: update.targetTemperature,
    }),

    deepHeating.roomModes$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      mode: update.mode,
    }),

    deepHeating.roomStatuses$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      isHeating: update.isHeating,
    }),

    deepHeating.roomAdjustments$.pipe(filter((x) => x.roomName === room.name)),
    (state, update) => ({
      ...state,
      adjustment: update.adjustment,
    }),

    deepHeating.roomTrvs$.pipe(
      filter((x) => x.roomName === room.name),
      mergeMap((x) =>
        x.climateEntityIds.map((y) => maintainTrvState(deepHeating, y))
      ),
      mergeAll()
    ),
    (state, _update) => ({
      ...state,
      radiators: addOrReplace(state.radiators, _update, 'name'),
    }),

    initialRoomState
  ).pipe(startWith<RoomState>(initialRoomState));
}

const emptyState: DeepHeatingState = { rooms: [] };

export function maintainState(
  deepHeating: DeepHeating
): Observable<DeepHeatingState> {
  return multiScan(
    deepHeating.rooms$.pipe(
      mergeMap((x) =>
        x.pipe(
          mergeMap((roomDefinition) =>
            maintainRoomState(deepHeating, roomDefinition)
          )
        )
      )
    ),
    (state, roomState) => ({
      ...state,
      rooms: addOrReplace(state.rooms, roomState, 'name'),
    }),

    deepHeating.heatingStatuses$,
    (state, heatingStatus) => ({
      ...state,
      isHeating: heatingStatus.isHeating,
    }),

    emptyState
  );
}
