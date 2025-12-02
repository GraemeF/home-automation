import { Chunk, Effect, Option, Stream } from 'effect';
import type { StreamEmit } from 'effect';
import { from, Observable } from 'rxjs';

/**
 * Converts an Effect Stream to an RxJS Observable.
 *
 * Uses RxJS 7's AsyncIterable support via `from()` for clean interop.
 * The stream is converted to an AsyncIterable which RxJS can consume directly.
 */
export const streamToObservable = <A, E>(
  stream: Stream.Stream<A, E>,
): Observable<A> => from(Stream.toAsyncIterable(stream));

/**
 * Converts an RxJS Observable to an Effect Stream.
 *
 * Creates an async Effect stream that subscribes to the observable and
 * emits values as they arrive. Properly handles errors and completion,
 * and cleans up the subscription when the stream is interrupted.
 */
export const observableToStream = <A>(
  observable: Observable<A>,
): Stream.Stream<A, Error> =>
  Stream.async<A, Error>((emit: StreamEmit.Emit<never, Error, A, void>) => {
    const subscription = observable.subscribe({
      next: (value) => void emit(Effect.succeed(Chunk.of(value))),
      error: (e) =>
        void emit(
          Effect.fail(
            Option.some(e instanceof Error ? e : new Error(String(e))),
          ),
        ),
      complete: () => void emit(Effect.fail(Option.none())),
    });
    return Effect.sync(subscription.unsubscribe.bind(subscription));
  });
