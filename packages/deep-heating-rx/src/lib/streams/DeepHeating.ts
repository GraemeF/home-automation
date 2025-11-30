import { FetchHttpClient } from '@effect/platform';
import {
  createHomeAssistantButtonEventProvider,
  createHomeAssistantHeatingProvider,
  createHomeAssistantSensorProvider,
  getEntityUpdatesStream,
  HomeAssistantApiLive,
  HomeAssistantConfigLive,
} from '@home-automation/deep-heating-home-assistant';
import { streamToObservable } from '@home-automation/rxx';
import {
  ClimateAction,
  ClimateEntityId,
  ClimateEntityStatus,
  ClimateTargetTemperature,
  ClimateTemperatureReading,
  getHeatingActions,
  GoodnightEventEntity,
  HeatingStatus,
  Home,
  HouseModeValue,
  RoomAdjustment,
  RoomClimateEntities,
  RoomClimateTargetTemperatures,
  RoomDecisionPoint,
  RoomDefinition,
  RoomMode,
  RoomSchedule,
  RoomSensors,
  RoomStatus,
  RoomTargetTemperature,
  RoomTemperature,
  RoomTrvModes,
  RoomTrvStatuses,
  RoomTrvTemperatures,
  RoomWeekHeatingSchedule,
  TemperatureSensorEntity,
  TrvControlState,
  TrvMode,
  TrvScheduledTargetTemperature,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Effect, HashSet, Layer, Predicate, Stream } from 'effect';
import { from, GroupedObservable, Observable, Subject } from 'rxjs';
import {
  distinctUntilChanged,
  groupBy,
  map,
  mergeAll,
  mergeMap,
  share,
  shareReplay,
} from 'rxjs/operators';
import { applyHeatingActions, applyTrvActions } from './actions';
import { getHouseModes } from './house/houseModes';
import { getRoomAdjustments } from './rooms/roomAdjustments';
import { getRoomDecisionPoints } from './rooms/roomDecisionPoints';
import { getRoomHiveHeatingSchedules } from './rooms/roomHiveHeatingSchedules';
import { getRoomModes } from './rooms/roomModes';
import { getRoomScheduledTargetTemperatures } from './rooms/roomScheduledTargetTemperatures';
import { getRoomSchedules } from './rooms/roomSchedules';
import { getRoomSensors } from './rooms/roomSensors';
import { getRoomsHeating } from './rooms/roomsHeating';
import { getRoomStatuses } from './rooms/roomStatuses';
import { getRoomTargetTemperatures } from './rooms/roomTargetTemperatures';
import { getRoomTemperatures } from './rooms/roomTemperatures';
import { getRoomTrvModes } from './rooms/roomTrvModes';
import { getRoomClimateEntities } from './rooms/roomTrvs';
import { getRoomTrvStatuses } from './rooms/roomTrvStatuses';
import { getRoomTrvTargetTemperatures } from './rooms/roomTrvTargetTemperatures';
import { getRoomTrvTemperatures } from './rooms/roomTrvTemperatures';
import { getTrvActions } from './trvs/trvActions';
import {
  getTrvDecisionPoints,
  TrvDecisionPoint,
} from './trvs/trvDecisionPoints';
import {
  getTrvDesiredTargetTemperatures,
  TrvDesiredTargetTemperature,
} from './trvs/trvDesiredTargetTemperatures';
import { getTrvModes } from './trvs/trvModes';
import { getTrvScheduledTargetTemperatures } from './trvs/trvScheduledTargetTemperatures';
import { getTrvWeekHeatingSchedules } from './trvs/trvSchedules';
import { getAnyHeating, getTrvsHeating } from './trvs/trvsHeating';
import { getTrvSynthesisedStatuses } from './trvs/trvSynthesisedStatuses';
import { getTrvTargetTemperatures } from './trvs/trvTargetTemperatures';
import { getTrvTemperatures } from './trvs/trvTemperatures';

const log = debug('deep-heating');

export interface DeepHeating {
  readonly temperatureSensorUpdate$: Observable<TemperatureSensorEntity>;
  readonly rooms$: Observable<GroupedObservable<string, RoomDefinition>>;
  readonly roomSensors$: Observable<Observable<RoomSensors>>;
  readonly roomTemperatures$: Observable<RoomTemperature>;
  readonly trvControlStates$: Observable<TrvControlState>;
  readonly trvStatuses$: Observable<ClimateEntityStatus>;
  readonly heatingStatuses$: Observable<HeatingStatus>;
  readonly trvReportedStatuses$: Observable<ClimateEntityStatus>;
  readonly heatingReportedStatuses$: Observable<HeatingStatus>;
  readonly trvHiveHeatingSchedules$: Observable<TrvWeekHeatingSchedule>;
  readonly roomTrvs$: Observable<RoomClimateEntities>;
  readonly roomHiveHeatingSchedules$: Observable<RoomWeekHeatingSchedule>;
  readonly roomSchedules$: Observable<RoomSchedule>;
  readonly roomTargetTemperatures$: Observable<RoomTargetTemperature>;
  readonly trvTargetTemperatures$: Observable<ClimateTargetTemperature>;
  readonly roomTrvTargetTemperatures$: Observable<RoomClimateTargetTemperatures>;
  readonly trvTemperatures$: Observable<ClimateTemperatureReading>;
  readonly roomTrvModes$: Observable<RoomTrvModes>;
  readonly roomTrvStatuses$: Observable<RoomTrvStatuses>;
  readonly trvModes$: Observable<TrvMode>;
  readonly roomModes$: Observable<RoomMode>;
  readonly roomStatuses$: Observable<RoomStatus>;
  readonly roomTrvTemperatures$: Observable<RoomTrvTemperatures>;
  readonly roomDecisionPoints$: Observable<RoomDecisionPoint>;
  readonly trvDesiredTargetTemperatures$: Observable<TrvDesiredTargetTemperature>;
  readonly trvDecisionPoints$: Observable<TrvDecisionPoint>;
  readonly trvScheduledTargetTemperatures$: Observable<TrvScheduledTargetTemperature>;
  readonly appliedTrvActions$: Observable<TrvControlState>;
  readonly trvSynthesisedStatuses: Observable<ClimateEntityStatus>;
  readonly trvActions$: Observable<ClimateAction>;
  readonly trvIds$: Observable<readonly ClimateEntityId[]>;
  readonly appliedHeatingActions$: Observable<HeatingStatus>;
  readonly heatingActions$: Observable<ClimateAction>;
  readonly roomAdjustments$: Observable<RoomAdjustment>;
  readonly roomScheduledTargetTemperatures$: Observable<RoomTargetTemperature>;
  readonly buttonEvents$: Observable<GoodnightEventEntity>;
  readonly houseModes$: Observable<HouseModeValue>;
  readonly trvsAnyHeating$: Observable<boolean>;
  readonly roomsAnyHeating$: Observable<boolean>;
  readonly trvsHeating$: Observable<HashSet.HashSet<ClimateEntityId>>;
  readonly roomsHeating$: Observable<HashSet.HashSet<string>>;
  readonly publishTrvControlState: (newState: TrvControlState) => void;
  readonly publishTrvStatus: (newStatus: ClimateEntityStatus) => void;
  readonly publishHeatingStatus: (newStatus: HeatingStatus) => void;
}

export function createDeepHeating(
  home: Home,
  initialRoomAdjustments: readonly RoomAdjustment[],
  roomAdjustmentCommands$: Observable<RoomAdjustment>,
): DeepHeating {
  const trvControlStateSubject: Subject<TrvControlState> =
    new Subject<TrvControlState>();
  const trvStatusSubject: Subject<ClimateEntityStatus> =
    new Subject<ClimateEntityStatus>();
  const heatingStatusSubject: Subject<HeatingStatus> =
    new Subject<HeatingStatus>();

  const publishTrvControlState = (newState: TrvControlState): void => {
    trvControlStateSubject.next(newState);
  };

  const publishTrvStatus = (newStatus: ClimateEntityStatus): void => {
    trvStatusSubject.next(newStatus);
  };

  const publishHeatingStatus = (newStatus: HeatingStatus): void => {
    heatingStatusSubject.next(newStatus);
  };

  const homeAssistantLayer = HomeAssistantApiLive.pipe(
    Layer.provide(HomeAssistantConfigLive),
    Layer.provide(FetchHttpClient.layer),
  );

  const runtime = homeAssistantLayer.pipe(
    Layer.toRuntime,
    Effect.scoped,
    Effect.runSync,
  );

  const entityUpdates$ = streamToObservable(
    getEntityUpdatesStream.pipe(Stream.provideLayer(homeAssistantLayer)),
  );

  const heatingProvider = createHomeAssistantHeatingProvider(
    home,
    entityUpdates$,
    runtime,
  );

  const temperatureSensorUpdate$ =
    createHomeAssistantSensorProvider(entityUpdates$).sensorUpdates$;
  const buttonEvents$ = createHomeAssistantButtonEventProvider(
    home,
    entityUpdates$,
  ).buttonPressEvents$;
  buttonEvents$.subscribe((x) =>
    log(x.entity_id, x.attributes.friendly_name, 'last happened at', x.state),
  );
  const houseModes$ = getHouseModes(buttonEvents$, home.sleepSwitchId);
  const logHouseMode = (x: HouseModeValue) => log('House is', x);
  houseModes$.subscribe(logHouseMode);
  const rooms$ = from(home.rooms).pipe(
    groupBy((roomDefinition) => roomDefinition.name),
  );
  const roomSensors$ = getRoomSensors(rooms$);
  const roomTemperatures$ = getRoomTemperatures(
    roomSensors$,
    temperatureSensorUpdate$,
  );
  const trvControlStates$ = trvControlStateSubject.pipe(
    groupBy((trvControlState) => trvControlState.climateEntityId),
    mergeMap((trvControlState) =>
      trvControlState.pipe(
        distinctUntilChanged<TrvControlState>(
          (a, b) =>
            a.mode === b.mode && a.targetTemperature === b.targetTemperature,
        ),
        shareReplay(1),
      ),
    ),
    share(),
  );
  const trvDisplayName = (trvId: ClimateEntityId): string =>
    `${
      home.rooms.find((x) => x.climateEntityIds.includes(trvId))?.name
    } (${trvId})`;
  trvControlStates$.subscribe((x) =>
    log(
      'TRV',
      trvDisplayName(x.climateEntityId),
      x.source === 'Device' ? 'is set to' : 'will be changed to',
      x.mode,
      x.targetTemperature,
    ),
  );

  const trvStatuses$ = trvStatusSubject.pipe(
    shareReplayLatestDistinctByKey((x) => x.climateEntityId),
  );

  trvStatuses$.subscribe((x) =>
    log(
      'TRV',
      trvDisplayName(x.climateEntityId),
      x.isHeating ? 'is heating' : 'is cooling',
    ),
  );

  const heatingStatuses$ = heatingStatusSubject.pipe(
    shareReplayLatestDistinctByKey((x) => x.heatingId),
  );

  heatingStatuses$.subscribe((x) =>
    log('Heating', x.heatingId, x.isHeating ? 'is heating' : 'is cooling'),
  );

  heatingProvider.trvApiUpdates$.subscribe((x) =>
    publishTrvControlState({
      climateEntityId: x.climateEntityId,
      mode: x.state.mode,
      targetTemperature: x.state.target,
      source: 'Device',
    }),
  );

  const trvReportedStatuses$ = heatingProvider.trvApiUpdates$.pipe(
    map((x) => ({
      climateEntityId: x.climateEntityId,
      isHeating: x.state.isHeating,
    })),
  );

  trvReportedStatuses$.subscribe(publishTrvStatus);

  const heatingReportedStatuses$ = heatingProvider.heatingApiUpdates$.pipe(
    map((x) => ({
      heatingId: x.heatingId,
      isHeating: x.state.isHeating,
      source: 'Device',
    })),
  );

  heatingReportedStatuses$.subscribe(publishHeatingStatus);

  const trvHiveHeatingSchedules$ = getTrvWeekHeatingSchedules(
    heatingProvider.trvApiUpdates$,
  );

  const roomTrvs$ = getRoomClimateEntities(rooms$);

  const roomHiveHeatingSchedules$ = getRoomHiveHeatingSchedules(
    roomTrvs$,
    trvHiveHeatingSchedules$,
  );

  const roomSchedules$ = getRoomSchedules(
    rooms$.pipe(mergeAll()),
    roomHiveHeatingSchedules$,
  );
  const roomAdjustments$ = getRoomAdjustments(
    [...initialRoomAdjustments],
    rooms$,
    roomAdjustmentCommands$,
  );
  const trvModes$ = getTrvModes(trvControlStates$);
  const roomTrvModes$ = getRoomTrvModes(roomTrvs$, trvModes$);
  const roomModes$ = getRoomModes(rooms$, houseModes$, roomTrvModes$);
  roomModes$.subscribe((x) => log(x.roomName, 'is', x.mode));
  const roomScheduledTargetTemperatures$ = getRoomScheduledTargetTemperatures(
    rooms$,
    roomSchedules$,
  );
  const roomTargetTemperatures$ = getRoomTargetTemperatures(
    rooms$,
    roomModes$,
    roomScheduledTargetTemperatures$,
    roomAdjustments$,
  );

  roomTargetTemperatures$.subscribe((x) =>
    log(x.roomName, 'should be', x.targetTemperature),
  );

  const trvTargetTemperatures$ = getTrvTargetTemperatures(trvControlStates$);
  const roomTrvTargetTemperatures$ = getRoomTrvTargetTemperatures(
    roomTrvs$,
    trvTargetTemperatures$,
  );
  const trvTemperatures$ = getTrvTemperatures(heatingProvider.trvApiUpdates$);
  const roomTrvTemperatures$ = getRoomTrvTemperatures(
    roomTrvs$,
    trvTemperatures$,
  );
  const roomTrvStatuses$ = getRoomTrvStatuses(roomTrvs$, trvStatuses$);
  const roomDecisionPoints$ = getRoomDecisionPoints(
    rooms$,
    roomTargetTemperatures$,
    roomTemperatures$,
    roomTrvTargetTemperatures$,
    roomTrvTemperatures$,
    roomTrvModes$,
  );
  const trvDecisionPoints$ = getTrvDecisionPoints(roomDecisionPoints$);
  const trvDesiredTargetTemperatures$ =
    getTrvDesiredTargetTemperatures(trvDecisionPoints$);
  const trvScheduledTargetTemperatures$ = getTrvScheduledTargetTemperatures(
    trvHiveHeatingSchedules$,
  );
  const trvIds$ = rooms$.pipe(
    mergeMap((roomDefinitions$) =>
      roomDefinitions$.pipe(
        map((roomDefinition) =>
          roomDefinition.climateEntityIds.filter(Predicate.isNotNull),
        ),
      ),
    ),
  );
  const trvActions$ = getTrvActions(
    trvIds$,
    trvDesiredTargetTemperatures$,
    trvControlStates$,
    trvTemperatures$,
    trvScheduledTargetTemperatures$,
  );
  const trvSynthesisedStatuses = getTrvSynthesisedStatuses(
    trvIds$,
    trvTemperatures$,
    trvControlStates$,
  );
  trvSynthesisedStatuses.subscribe(publishTrvStatus);

  const publishTrvAction = (newAction: ClimateAction): void => {
    heatingProvider.trvActions.next(newAction);
  };

  const publishHeatingAction = (newAction: ClimateAction): void => {
    heatingProvider.heatingActions.next(newAction);
  };

  const appliedTrvActions$ = applyTrvActions(
    trvIds$,
    trvActions$,
    trvControlStates$,
    trvScheduledTargetTemperatures$,
    publishTrvAction,
  );
  const trvsHeating$ = getTrvsHeating(trvStatuses$);
  trvsHeating$.subscribe((x) => log('TRVs', Array.from(x), 'are heating'));

  const roomsHeating$ = getRoomsHeating(roomDecisionPoints$);

  const trvsAnyHeating$ = getAnyHeating(trvsHeating$);
  trvsAnyHeating$.subscribe((x) =>
    log(x ? 'Some TRVs are heating' : 'No TRVs are heating'),
  );

  const roomsAnyHeating$ = getAnyHeating(roomsHeating$);
  roomsAnyHeating$.subscribe((x) =>
    log(x ? 'Some rooms are heating' : 'No rooms are heating'),
  );

  const heatingActions$ = getHeatingActions(
    home.heatingId,
    heatingStatuses$,
    roomsAnyHeating$,
  );
  heatingActions$.subscribe((x) =>
    log(
      'Heating',
      x.climateEntityId,
      'should change to',
      x.mode,
      x.targetTemperature,
    ),
  );

  const appliedHeatingActions$ = applyHeatingActions(
    heatingActions$,
    publishHeatingAction,
  );
  appliedHeatingActions$.subscribe((x) => {
    log(
      'Heating',
      x.heatingId,
      'has been changed to',
      x.isHeating ? 'heating' : 'cooling',
    );
    publishHeatingStatus(x);
  });

  const roomStatuses$ = getRoomStatuses(roomTrvStatuses$);

  appliedTrvActions$.subscribe(publishTrvControlState);

  return {
    temperatureSensorUpdate$,
    rooms$,
    roomSensors$,
    roomTemperatures$,
    trvControlStates$,
    trvStatuses$,
    heatingStatuses$,
    trvReportedStatuses$,
    heatingReportedStatuses$,
    trvHiveHeatingSchedules$,
    roomTrvs$,
    roomHiveHeatingSchedules$,
    roomSchedules$,
    roomTargetTemperatures$,
    trvTargetTemperatures$,
    roomTrvTargetTemperatures$,
    trvTemperatures$,
    roomTrvModes$,
    roomTrvStatuses$,
    trvModes$,
    roomModes$,
    roomStatuses$,
    roomTrvTemperatures$,
    roomDecisionPoints$,
    trvDesiredTargetTemperatures$,
    trvDecisionPoints$,
    trvScheduledTargetTemperatures$,
    appliedTrvActions$,
    trvSynthesisedStatuses,
    trvActions$,
    trvIds$,
    appliedHeatingActions$,
    heatingActions$,
    roomAdjustments$,
    roomScheduledTargetTemperatures$,
    buttonEvents$,
    houseModes$,
    trvsAnyHeating$,
    roomsAnyHeating$,
    trvsHeating$,
    roomsHeating$,
    publishTrvControlState,
    publishTrvStatus,
    publishHeatingStatus,
  };
}
