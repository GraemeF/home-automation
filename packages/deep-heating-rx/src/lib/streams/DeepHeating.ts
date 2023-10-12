import {
  createHomeAssistantButtonEventProvider,
  createHomeAssistantHeatingProvider,
  createHomeAssistantSensorProvider,
  getEntityUpdates,
  HomeAssistantApiLive,
  HomeAssistantConfigLive,
} from '@home-automation/deep-heating-home-assistant';
import {
  ButtonEvent,
  getHeatingActions,
  HeatingAction,
  HeatingStatus,
  Home,
  HouseModeValue,
  RoomAdjustment,
  RoomDecisionPoint,
  RoomDefinition,
  RoomMode,
  RoomSchedule,
  RoomSensors,
  RoomStatus,
  RoomTargetTemperature,
  RoomTemperature,
  RoomTrvModes,
  RoomTrvs,
  RoomTrvStatuses,
  RoomTrvTargetTemperatures,
  RoomTrvTemperatures,
  RoomWeekHeatingSchedule,
  TemperatureSensorUpdate,
  TrvAction,
  TrvControlState,
  TrvMode,
  TrvScheduledTargetTemperature,
  TrvStatus,
  TrvTargetTemperature,
  TrvTemperature,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import debug from 'debug';
import { Effect, Layer, pipe, Predicate } from 'effect';
import { from, GroupedObservable, Observable, Subject } from 'rxjs';
import {
  distinctUntilChanged,
  filter,
  groupBy,
  map,
  mergeAll,
  mergeMap,
  share,
  shareReplay,
} from 'rxjs/operators';
import { isDeepStrictEqual } from 'util';
import { applyHeatingActions, applyTrvActions } from './actions';
import { getHouseModes } from './house/houseModes';
import { getRoomAdjustments } from './rooms/roomAdjustments';
import { getRoomDecisionPoints } from './rooms/roomDecisionPoints';
import { getRoomHiveHeatingSchedules } from './rooms/roomHiveHeatingSchedules';
import { getRoomModes } from './rooms/roomModes';
import { getRoomScheduledTargetTemperatures } from './rooms/roomScheduledTargetTemperatures';
import { getRoomSchedules } from './rooms/roomSchedules';
import { getRoomSensors, isTemperatureSensorUpdate } from './rooms/roomSensors';
import { getRoomsHeating } from './rooms/roomsHeating';
import { getRoomStatuses } from './rooms/roomStatuses';
import { getRoomTargetTemperatures } from './rooms/roomTargetTemperatures';
import { getRoomTemperatures } from './rooms/roomTemperatures';
import { getRoomTrvModes } from './rooms/roomTrvModes';
import { getRoomTrvs } from './rooms/roomTrvs';
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

export class DeepHeating {
  readonly temperatureSensorUpdate$: Observable<TemperatureSensorUpdate>;
  readonly rooms$: Observable<GroupedObservable<string, RoomDefinition>>;
  readonly roomSensors$: Observable<Observable<RoomSensors>>;
  readonly roomTemperatures$: Observable<RoomTemperature>;
  readonly trvControlStates$: Observable<TrvControlState>;
  readonly trvStatuses$: Observable<TrvStatus>;
  readonly heatingStatuses$: Observable<HeatingStatus>;
  readonly trvReportedStatuses$: Observable<TrvStatus>;
  readonly heatingReportedStatuses$: Observable<HeatingStatus>;
  readonly trvHiveHeatingSchedules$: Observable<TrvWeekHeatingSchedule>;
  readonly roomTrvs$: Observable<RoomTrvs>;
  readonly roomHiveHeatingSchedules$: Observable<RoomWeekHeatingSchedule>;
  readonly roomSchedules$: Observable<RoomSchedule>;
  readonly roomTargetTemperatures$: Observable<RoomTargetTemperature>;
  readonly trvTargetTemperatures$: Observable<TrvTargetTemperature>;
  readonly roomTrvTargetTemperatures$: Observable<RoomTrvTargetTemperatures>;
  readonly trvTemperatures$: Observable<TrvTemperature>;
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
  readonly trvSynthesisedStatuses: Observable<TrvStatus>;
  readonly trvActions$: Observable<TrvAction>;
  readonly trvIds$: Observable<string[]>;
  readonly appliedHeatingActions$: Observable<HeatingStatus>;
  readonly heatingActions$: Observable<HeatingAction>;
  readonly roomAdjustments$: Observable<RoomAdjustment>;
  readonly roomScheduledTargetTemperatures$: Observable<RoomTargetTemperature>;
  readonly buttonEvents$: Observable<ButtonEvent>;
  readonly houseModes$: Observable<HouseModeValue>;
  readonly trvsAnyHeating$: Observable<boolean>;
  readonly roomsAnyHeating$: Observable<boolean>;
  readonly trvsHeating$: Observable<Set<string>>;
  readonly roomsHeating$: Observable<Set<string>>;

  private readonly trvControlStateSubject: Subject<TrvControlState> =
    new Subject<TrvControlState>();
  private readonly trvStatusSubject: Subject<TrvStatus> =
    new Subject<TrvStatus>();
  private readonly heatingStatusSubject: Subject<HeatingStatus> =
    new Subject<HeatingStatus>();

  constructor(
    home: Home,
    initialRoomAdjustments: RoomAdjustment[],
    roomAdjustmentCommands$: Observable<RoomAdjustment>
  ) {
    const runtime = pipe(
      HomeAssistantApiLive.pipe(Layer.use(HomeAssistantConfigLive)),
      Layer.toRuntime,
      Effect.scoped,
      Effect.runSync
    );

    const entityUpdates$ = getEntityUpdates(runtime);

    const heatingProvider = createHomeAssistantHeatingProvider(
      home,
      entityUpdates$,
      runtime
    );
    const sensorProvider = createHomeAssistantSensorProvider(entityUpdates$);

    this.temperatureSensorUpdate$ = sensorProvider.sensorUpdates$.pipe(
      filter(isTemperatureSensorUpdate)
    );
    this.buttonEvents$ = createHomeAssistantButtonEventProvider(
      home,
      entityUpdates$
    ).buttonPressEvents$;
    this.buttonEvents$.subscribe((x) =>
      log(
        'Button',
        x.switchId,
        x.switchName,
        x.buttonIndex,
        'event',
        x.eventType
      )
    );
    this.houseModes$ = getHouseModes(this.buttonEvents$, home.sleepSwitchId);
    this.houseModes$.subscribe((x) => log('House is', x));
    this.rooms$ = from(home.rooms).pipe(
      groupBy((roomDefinition) => roomDefinition.name)
    );
    this.roomSensors$ = getRoomSensors(this.rooms$);
    this.roomTemperatures$ = getRoomTemperatures(
      this.roomSensors$,
      this.temperatureSensorUpdate$
    );
    this.trvControlStates$ = this.trvControlStateSubject.pipe(
      groupBy((trvControlState) => trvControlState.trvId),
      mergeMap((trvControlState) =>
        trvControlState.pipe(
          distinctUntilChanged<TrvControlState>(isDeepStrictEqual),
          shareReplay(1)
        )
      ),
      share()
    );
    const trvDisplayName = (trvId: string): string =>
      `${
        home.rooms.find((x) => x.trvControlIds.includes(trvId))?.name
      } (${trvId})`;
    this.trvControlStates$.subscribe((x) =>
      log(
        'TRV',
        trvDisplayName(x.trvId),
        x.source === 'Device' ? 'is set to' : 'will be changed to',
        x.mode,
        x.targetTemperature
      )
    );

    this.trvStatuses$ = this.trvStatusSubject.pipe(
      shareReplayLatestDistinctByKey((x) => x.trvId)
    );

    this.trvStatuses$.subscribe((x) =>
      log(
        'TRV',
        trvDisplayName(x.trvId),
        x.isHeating ? 'is heating' : 'is cooling'
      )
    );

    this.heatingStatuses$ = this.heatingStatusSubject.pipe(
      shareReplayLatestDistinctByKey((x) => x.heatingId)
    );

    this.heatingStatuses$.subscribe((x) =>
      log('Heating', x.heatingId, x.isHeating ? 'is heating' : 'is cooling')
    );

    heatingProvider.trvApiUpdates$.subscribe((x) =>
      this.publishTrvControlState({
        trvId: x.trvId,
        mode: x.state.mode,
        targetTemperature: x.state.target,
        source: 'Device',
      })
    );

    this.trvReportedStatuses$ = heatingProvider.trvApiUpdates$.pipe(
      map((x) => ({
        trvId: x.trvId,
        isHeating: x.state.isHeating,
      }))
    );

    this.trvReportedStatuses$.subscribe((x) => this.publishTrvStatus(x));

    this.heatingReportedStatuses$ = heatingProvider.heatingApiUpdates$.pipe(
      map((x) => ({
        heatingId: x.heatingId,
        isHeating: x.state.isHeating,
        source: 'Device',
      }))
    );

    this.heatingReportedStatuses$.subscribe((x) =>
      this.publishHeatingStatus(x)
    );

    this.trvHiveHeatingSchedules$ = getTrvWeekHeatingSchedules(
      heatingProvider.trvApiUpdates$
    );

    this.roomTrvs$ = getRoomTrvs(this.rooms$);

    this.roomHiveHeatingSchedules$ = getRoomHiveHeatingSchedules(
      this.roomTrvs$,
      this.trvHiveHeatingSchedules$
    );

    this.roomSchedules$ = getRoomSchedules(
      this.rooms$.pipe(mergeAll()),
      this.roomHiveHeatingSchedules$
    );
    this.roomAdjustments$ = getRoomAdjustments(
      initialRoomAdjustments,
      this.rooms$,
      roomAdjustmentCommands$
    );
    this.trvModes$ = getTrvModes(this.trvControlStates$);
    this.roomTrvModes$ = getRoomTrvModes(this.roomTrvs$, this.trvModes$);
    this.roomModes$ = getRoomModes(
      this.rooms$,
      this.houseModes$,
      this.roomTrvModes$
    );
    this.roomModes$.subscribe((x) => log(x.roomName, 'is', x.mode));
    this.roomScheduledTargetTemperatures$ = getRoomScheduledTargetTemperatures(
      this.rooms$,
      this.roomSchedules$
    );
    this.roomTargetTemperatures$ = getRoomTargetTemperatures(
      this.rooms$,
      this.roomModes$,
      this.roomScheduledTargetTemperatures$,
      this.roomAdjustments$
    );

    this.roomTargetTemperatures$.subscribe((x) =>
      log(x.roomName, 'should be', x.targetTemperature)
    );

    this.trvTargetTemperatures$ = getTrvTargetTemperatures(
      this.trvControlStates$
    );
    this.roomTrvTargetTemperatures$ = getRoomTrvTargetTemperatures(
      this.roomTrvs$,
      this.trvTargetTemperatures$
    );
    this.trvTemperatures$ = getTrvTemperatures(heatingProvider.trvApiUpdates$);
    this.roomTrvTemperatures$ = getRoomTrvTemperatures(
      this.roomTrvs$,
      this.trvTemperatures$
    );
    this.roomTrvStatuses$ = getRoomTrvStatuses(
      this.roomTrvs$,
      this.trvStatuses$
    );
    this.roomDecisionPoints$ = getRoomDecisionPoints(
      this.rooms$,
      this.roomTargetTemperatures$,
      this.roomTemperatures$,
      this.roomTrvTargetTemperatures$,
      this.roomTrvTemperatures$,
      this.roomTrvModes$
    );
    this.trvDecisionPoints$ = getTrvDecisionPoints(this.roomDecisionPoints$);
    this.trvDesiredTargetTemperatures$ = getTrvDesiredTargetTemperatures(
      this.trvDecisionPoints$
    );
    this.trvScheduledTargetTemperatures$ = getTrvScheduledTargetTemperatures(
      this.trvHiveHeatingSchedules$
    );
    this.trvIds$ = this.rooms$.pipe(
      mergeMap((roomDefinitions$) =>
        roomDefinitions$.pipe(
          map((roomDefinition) =>
            roomDefinition.trvControlIds.filter(Predicate.isNotNull)
          )
        )
      )
    );
    this.trvActions$ = getTrvActions(
      this.trvIds$,
      this.trvDesiredTargetTemperatures$,
      this.trvControlStates$,
      this.trvTemperatures$,
      this.trvScheduledTargetTemperatures$
    );
    this.trvSynthesisedStatuses = getTrvSynthesisedStatuses(
      this.trvIds$,
      this.trvTemperatures$,
      this.trvControlStates$
    );
    this.trvSynthesisedStatuses.subscribe((x) => this.publishTrvStatus(x));
    this.appliedTrvActions$ = applyTrvActions(
      this.trvIds$,
      this.trvActions$,
      this.trvControlStates$,
      this.trvScheduledTargetTemperatures$,
      publishTrvAction
    );
    this.trvsHeating$ = getTrvsHeating(this.trvStatuses$);
    this.trvsHeating$.subscribe((x) =>
      log('TRVs', Array.from(x), 'are heating')
    );

    this.roomsHeating$ = getRoomsHeating(this.roomDecisionPoints$);

    this.trvsAnyHeating$ = getAnyHeating(this.trvsHeating$);
    this.trvsAnyHeating$.subscribe((x) =>
      log(x ? 'Some TRVs are heating' : 'No TRVs are heating')
    );

    this.roomsAnyHeating$ = getAnyHeating(this.roomsHeating$);
    this.roomsAnyHeating$.subscribe((x) =>
      log(x ? 'Some rooms are heating' : 'No rooms are heating')
    );

    this.heatingActions$ = getHeatingActions(
      home.heatingId,
      this.heatingStatuses$,
      this.roomsAnyHeating$
    );
    this.heatingActions$.subscribe((x) =>
      log(
        'Heating',
        x.heatingId,
        'should change to',
        x.mode,
        x.targetTemperature
      )
    );

    this.appliedHeatingActions$ = applyHeatingActions(
      this.heatingActions$,
      publishHeatingAction
    );
    this.appliedHeatingActions$.subscribe((x) => {
      log(
        'Heating',
        x.heatingId,
        'has been changed to',
        x.isHeating ? 'heating' : 'cooling'
      );
      this.publishHeatingStatus(x);
    });

    this.roomStatuses$ = getRoomStatuses(this.roomTrvStatuses$);

    this.appliedTrvActions$.subscribe((x) => this.publishTrvControlState(x));

    function publishTrvAction(newAction: TrvAction): void {
      heatingProvider.trvActions.next(newAction);
    }

    function publishHeatingAction(newAction: HeatingAction): void {
      heatingProvider.heatingActions.next(newAction);
    }
  }

  publishTrvControlState(newState: TrvControlState): void {
    this.trvControlStateSubject.next(newState);
  }

  publishTrvStatus(newStatus: TrvStatus): void {
    this.trvStatusSubject.next(newStatus);
  }

  publishHeatingStatus(newStatus: HeatingStatus): void {
    this.heatingStatusSubject.next(newStatus);
  }
}
