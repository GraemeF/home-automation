import { Schema } from 'effect';
import { createDeepHeating } from '@home-automation/deep-heating-rx';
import { maintainState } from '@home-automation/deep-heating-state';
import {
  DeepHeatingState,
  Home,
  RoomAdjustment,
} from '@home-automation/deep-heating-types';
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

interface SocketEvent<T> {
  io: SocketIO.Server;
  client: SocketIO.Socket;
  data: T;
}

export class SocketServer {
  private readonly io$: Observable<SocketIO.Server>;
  private readonly connection$: Observable<{
    io: SocketIO.Server;
    client: SocketIO.Socket;
  }>;
  private readonly disconnect$: Observable<SocketIO.Socket>;
  private readonly subscription: Subscription;
  private readonly saveRoomAdjustmentsSubscription: Subscription;
  private readonly state$: Observable<DeepHeatingState>;

  constructor(
    server: Server,
    home: Home,
    initialRoomAdjustments: RoomAdjustment[],
    saveRoomAdjustments: (roomAdjustments: RoomAdjustment[]) => void,
    opts?: Partial<ServerOptions>,
  ) {
    this.io$ = of(new SocketIO.Server(server, opts));

    this.connection$ = this.io$.pipe(
      switchMap((io) =>
        fromEvent(io, 'connection').pipe(
          map((client) => ({ io, client: client as SocketIO.Socket })),
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
      ([state, io]) => io.emit('State', state),
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
