import { describe, expect, it } from 'bun:test';
import { Effect, Stream } from 'effect';
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

    it('handles streams that emit over time', async () => {
      const stream = Stream.make(1, 2, 3).pipe(
        Stream.tap(() => Effect.sleep('10 millis')),
      );
      const observable = streamToObservable(stream);

      const values = await firstValueFrom(observable.pipe(toArray()));

      expect(values).toEqual([1, 2, 3]);
    });
  });

  describe('observableToStream', () => {
    it('converts a simple observable to a stream', async () => {
      const observable = new Observable<number>((subscriber) => {
        subscriber.next(1);
        subscriber.next(2);
        subscriber.next(3);
        subscriber.complete();
      });

      const stream = observableToStream(observable);
      const result = await Effect.runPromise(Stream.runCollect(stream));

      expect(Array.from(result)).toEqual([1, 2, 3]);
    });

    it('converts an empty observable to an empty stream', async () => {
      const observable = new Observable<number>((subscriber) =>
        subscriber.complete(),
      );

      const stream = observableToStream(observable);
      const result = await Effect.runPromise(Stream.runCollect(stream));

      expect(Array.from(result)).toEqual([]);
    });

    it('propagates errors from the observable to the stream', async () => {
      const observable = new Observable<number>((subscriber) => {
        subscriber.error(new Error('observable error'));
      });

      const stream = observableToStream(observable);

      await expect(
        Effect.runPromise(Stream.runCollect(stream)),
      ).rejects.toThrow('observable error');
    });

    it('handles observables that emit over time', async () => {
      const observable = new Observable<number>((subscriber) => {
        setTimeout(() => subscriber.next(1), 10);
        setTimeout(() => subscriber.next(2), 20);
        setTimeout(() => subscriber.next(3), 30);
        setTimeout(subscriber.complete.bind(subscriber), 40);
      });

      const stream = observableToStream(observable);
      const result = await Effect.runPromise(Stream.runCollect(stream));

      expect(Array.from(result)).toEqual([1, 2, 3]);
    });

    it('cleans up subscription when stream is interrupted', async () => {
      let unsubscribed = false;
      const observable = new Observable<number>((subscriber) => {
        const interval = setInterval(() => subscriber.next(1), 10);
        return () => {
          clearInterval(interval);
          unsubscribed = true;
        };
      });

      const stream = observableToStream(observable);

      // Take only one element, which should trigger cleanup
      await Effect.runPromise(stream.pipe(Stream.take(1), Stream.runCollect));

      // Give a moment for cleanup
      await new Promise((resolve) => setTimeout(resolve, 50));

      expect(unsubscribed).toBe(true);
    });
  });

  describe('round-trip conversions', () => {
    it('preserves values through stream -> observable -> stream', async () => {
      const originalStream = Stream.make(1, 2, 3);
      const observable = streamToObservable(originalStream);
      const backToStream = observableToStream(observable);

      const result = await Effect.runPromise(Stream.runCollect(backToStream));

      expect(Array.from(result)).toEqual([1, 2, 3]);
    });

    it('preserves values through observable -> stream -> observable', async () => {
      const originalObservable = new Observable<number>((subscriber) => {
        subscriber.next(1);
        subscriber.next(2);
        subscriber.next(3);
        subscriber.complete();
      });

      const stream = observableToStream(originalObservable);
      const backToObservable = streamToObservable(stream);

      const values = await firstValueFrom(backToObservable.pipe(toArray()));

      expect(values).toEqual([1, 2, 3]);
    });
  });
});
