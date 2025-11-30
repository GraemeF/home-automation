import { Runtime, Schema } from 'effect';
import { createDeepHeating } from '@home-automation/deep-heating-rx';
import { HomeAssistantApi } from '@home-automation/deep-heating-home-assistant';
import { maintainState } from '@home-automation/deep-heating-state';
import {
  ClientToServerEvents,
  DeepHeatingState,
  Home,
  HomeAssistantEntity,
  RoomAdjustment,
  ServerToClientEvents,
} from '@home-automation/deep-heating-types';
// eslint-disable-next-line effect/prefer-effect-platform -- socket.io server being migrated away
import { Server } from 'http';
import { Observable, Subscription, combineLatest, fromEvent, of } from 'rxjs';
import {
  distinctUntilChanged,
  map,
  mergeMap,
  share,
  switchMap,
  takeUntil,
  throttleTime,
  withLatestFrom,
} from 'rxjs/operators';
import * as SocketIO from 'socket.io';
import { ServerOptions } from 'socket.io';
import { isDeepStrictEqual } from 'util';

type TypedServer = SocketIO.Server<ClientToServerEvents, ServerToClientEvents>;
type TypedSocket = SocketIO.Socket<ClientToServerEvents, ServerToClientEvents>;

interface SocketEvent<T> {
  io: TypedServer;
  client: TypedSocket;
  data: T;
}

export class SocketServer {
  private readonly io$: Observable<TypedServer>;
  private readonly connection$: Observable<{
    io: TypedServer;
    client: TypedSocket;
  }>;
  private readonly disconnect$: Observable<TypedSocket>;
  private readonly subscription: Subscription;
  private readonly saveRoomAdjustmentsSubscription: Subscription;
  private readonly state$: Observable<DeepHeatingState>;

  constructor(
    server: Server,
    home: Home,
    initialRoomAdjustments: RoomAdjustment[],
    saveRoomAdjustments: (roomAdjustments: RoomAdjustment[]) => void,
    entityUpdates$: Observable<HomeAssistantEntity>,
    homeAssistantRuntime: Runtime.Runtime<HomeAssistantApi>,
    opts?: Partial<ServerOptions>,
  ) {
    this.io$ = of(
      new SocketIO.Server<ClientToServerEvents, ServerToClientEvents>(
        server,
        opts,
      ),
    );

    this.connection$ = this.io$.pipe(
      switchMap((io) =>
        fromEvent(io, 'connection').pipe(
          map((client) => ({ io, client: client as TypedSocket })),
        ),
      ),
    );

    this.disconnect$ = this.connection$.pipe(
      mergeMap(({ client }) =>
        fromEvent(client, 'disconnect').pipe(map(() => client)),
      ),
    );

    const roomAdjustments$ = this.events<RoomAdjustment>('adjust_room').pipe(
      map(({ data }: { data: RoomAdjustment }) => data),
      distinctUntilChanged<RoomAdjustment>(isDeepStrictEqual),
      share(),
    );
    const deepHeating = createDeepHeating(
      home,
      initialRoomAdjustments,
      roomAdjustments$,
      entityUpdates$,
      homeAssistantRuntime,
    );

    this.state$ = maintainState(deepHeating).pipe(
      throttleTime(100, undefined, { leading: true, trailing: true }),
    );

    this.connection$
      .pipe(withLatestFrom(this.state$))
      .subscribe(([{ client }, state]) => {
        client.emit('State', Schema.encodeSync(DeepHeatingState)(state));
      });

    this.subscription = combineLatest([this.state$, this.io$]).subscribe(
      ([state, io]) =>
        io.emit('State', Schema.encodeSync(DeepHeatingState)(state)),
    );

    this.saveRoomAdjustmentsSubscription = this.state$
      .pipe(
        map((state) =>
          state.rooms.map((room) => ({
            roomName: room.name,
            adjustment: room.adjustment,
          })),
        ),
      )
      .subscribe(saveRoomAdjustments);
  }

  public logConnections(): void {
    this.connection$.subscribe();
    this.disconnect$.subscribe();
  }

  public dispose(): void {
    this.saveRoomAdjustmentsSubscription.unsubscribe();
    this.subscription.unsubscribe();
  }

  private events<T>(eventName: string): Observable<SocketEvent<T>> {
    return this.connection$.pipe(
      mergeMap(({ io, client }) =>
        fromEvent<T>(client, eventName).pipe(
          takeUntil(fromEvent(client, 'disconnect')),
          map((data: T) => ({ io, client, data })),
        ),
      ),
    );
  }
}
