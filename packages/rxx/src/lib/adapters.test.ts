import { describe, expect, it } from '@codeforbreakfast/bun-test-effect';
import { Effect, pipe, Stream } from 'effect';
import { firstValueFrom, Observable, toArray } from 'rxjs';
import { observableToStream, streamToObservable } from './adapters';

describe('Effect/RxJS adapters', () => {
  describe('streamToObservable', () => {
    it('converts a simple stream to an observable', async () => {
      const stream = Stream.make(1, 2, 3);
      const observable = streamToObservable(stream);

      const values = await firstValueFrom(observable.pipe(toArray()));

      expect(values).toEqual([1, 2, 3]);
    });

    it('converts an empty stream to an observable that completes immediately', async () => {
      const observable = streamToObservable(Stream.empty);

      const values = await firstValueFrom(observable.pipe(toArray()));

      expect(values).toEqual([]);
    });

    it('propagates errors from the stream to the observable', async () => {
      const stream = Stream.fail(new Error('test error'));
      const observable = streamToObservable(stream);

      await expect(firstValueFrom(observable)).rejects.toThrow('test error');
    });

    it.live('handles streams that emit over time', () =>
      pipe(
        Stream.make(1, 2, 3),
        Stream.tap(() => Effect.sleep('10 millis')),
        streamToObservable,
        (observable) =>
          Effect.promise(() => firstValueFrom(observable.pipe(toArray()))),
        Effect.flatMap((values) =>
          Effect.sync(() => {
            expect(values).toEqual([1, 2, 3]);
          }),
        ),
      ),
    );
  });

  describe('observableToStream', () => {
    it.effect('converts a simple observable to a stream', () =>
      pipe(
        new Observable<number>((subscriber) => {
          subscriber.next(1);
          subscriber.next(2);
          subscriber.next(3);
          subscriber.complete();
        }),
        observableToStream,
        Stream.runCollect,
        Effect.map((result) => {
          expect(Array.from(result)).toEqual([1, 2, 3]);
        }),
      ),
    );

    it.effect('converts an empty observable to an empty stream', () =>
      pipe(
        new Observable<number>((subscriber) => subscriber.complete()),
        observableToStream,
        Stream.runCollect,
        Effect.map((result) => {
          expect(Array.from(result)).toEqual([]);
        }),
      ),
    );

    it.effect('propagates errors from the observable to the stream', () =>
      pipe(
        new Observable<number>((subscriber) => {
          subscriber.error(new Error('observable error'));
        }),
        observableToStream,
        Stream.runCollect,
        Effect.flip,
        Effect.map((error) => {
          expect(error).toBeInstanceOf(Error);
          if (error instanceof Error) {
            expect(error.message).toBe('observable error');
          }
        }),
      ),
    );

    it.effect('handles observables that emit over time', () =>
      pipe(
        new Observable<number>((subscriber) => {
          setTimeout(() => subscriber.next(1), 10);
          setTimeout(() => subscriber.next(2), 20);
          setTimeout(() => subscriber.next(3), 30);
          setTimeout(subscriber.complete.bind(subscriber), 40);
        }),
        observableToStream,
        Stream.runCollect,
        Effect.map((result) => {
          expect(Array.from(result)).toEqual([1, 2, 3]);
        }),
      ),
    );

    it.live('cleans up subscription when stream is interrupted', () => {
      let unsubscribed = false;

      return pipe(
        new Observable<number>((subscriber) => {
          const interval = setInterval(() => subscriber.next(1), 10);
          return () => {
            clearInterval(interval);
            unsubscribed = true;
          };
        }),
        observableToStream,
        Stream.take(1),
        Stream.runCollect,
        Effect.andThen(
          Effect.promise(() => new Promise((r) => setTimeout(r, 50))),
        ),
        Effect.map(() => {
          expect(unsubscribed).toBe(true);
        }),
      );
    });
  });

  describe('round-trip conversions', () => {
    it.effect('preserves values through stream -> observable -> stream', () =>
      pipe(
        Stream.make(1, 2, 3),
        streamToObservable,
        observableToStream,
        Stream.runCollect,
        Effect.map((result) => {
          expect(Array.from(result)).toEqual([1, 2, 3]);
        }),
      ),
    );

    it('preserves values through observable -> stream -> observable', async () => {
      const values = await firstValueFrom(
        pipe(
          new Observable<number>((subscriber) => {
            subscriber.next(1);
            subscriber.next(2);
            subscriber.next(3);
            subscriber.complete();
          }),
          observableToStream,
          streamToObservable,
        ).pipe(toArray()),
      );

      expect(values).toEqual([1, 2, 3]);
    });
  });
});
