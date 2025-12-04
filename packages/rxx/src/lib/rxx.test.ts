import { describe, it } from '@codeforbreakfast/bun-test-effect';
import { Array, Data, Effect, Option, pipe, Stream } from 'effect';
import { Subject } from 'rxjs';
import { observableToStream } from './adapters';
import { shareReplayLatestDistinctByKey } from './rxx';

interface TrvTemperature {
  readonly climateEntityId: string;
  readonly temperature: number;
}

const AssertionError = Data.TaggedError('AssertionError')<{
  readonly message: string;
}>;

type AssertionError = ReturnType<typeof AssertionError>;

const assertEqual = <A>(
  actual: A,
  expected: A,
): Effect.Effect<void, AssertionError> =>
  Effect.if(JSON.stringify(actual) === JSON.stringify(expected), {
    onTrue: () => Effect.void,
    onFalse: () =>
      Effect.fail(
        AssertionError({
          message: `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
        }),
      ),
  });

const assertLength = (
  arr: readonly TrvTemperature[],
  expected: number,
): Effect.Effect<readonly TrvTemperature[], AssertionError> =>
  Effect.if(arr.length === expected, {
    onTrue: () => Effect.succeed(arr),
    onFalse: () =>
      Effect.fail(
        AssertionError({
          message: `Expected ${String(expected)} values, got ${String(arr.length)}`,
        }),
      ),
  });

const assertUniqueKeys = (
  arr: readonly TrvTemperature[],
  expected: number,
): Effect.Effect<readonly TrvTemperature[], AssertionError> =>
  Effect.if(new Set(arr.map((v) => v.climateEntityId)).size === expected, {
    onTrue: () => Effect.succeed(arr),
    onFalse: () =>
      Effect.fail(
        AssertionError({ message: `Expected ${String(expected)} unique keys` }),
      ),
  });

const assertTrvMatches = (
  value: TrvTemperature,
  expectedId: string,
  expectedTemp: number,
): Effect.Effect<void, AssertionError> =>
  pipe(
    assertEqual(value.climateEntityId, expectedId),
    Effect.andThen(assertEqual(value.temperature, expectedTemp)),
  );

const assertLastValue = (
  arr: readonly TrvTemperature[],
  expectedId: string,
  expectedTemp: number,
): Effect.Effect<void, AssertionError> =>
  pipe(
    arr,
    Array.last,
    Option.match({
      onNone: () =>
        Effect.fail(AssertionError({ message: 'Expected a last value' })),
      onSome: (value) => assertTrvMatches(value, expectedId, expectedTemp),
    }),
  );

describe('shareReplayLatestDistinctByKey', () => {
  it.effect(
    'replays latest value for each key when new subscriber joins',
    () => {
      const source$ = new Subject<TrvTemperature>();
      const replayed$ = source$.pipe(
        shareReplayLatestDistinctByKey((x) => x.climateEntityId),
      );

      // Subscribe first to establish the shareReplay cache
      const firstSub = replayed$.subscribe();

      // Emit values
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
      source$.next({ climateEntityId: 'office', temperature: 20 });
      source$.next({ climateEntityId: 'lounge', temperature: 19 });

      // Clean up first subscriber
      firstSub.unsubscribe();

      // Late subscriber should receive replayed values
      return pipe(
        replayed$,
        observableToStream,
        Stream.take(3),
        Stream.runCollect,
        Effect.map(Array.fromIterable),
        Effect.flatMap((arr) => assertLength(arr, 3)),
        Effect.andThen((arr) =>
          assertEqual(arr.map((v) => v.climateEntityId).sort(), [
            'bedroom',
            'lounge',
            'office',
          ]),
        ),
      );
    },
  );

  it.effect('emits all keys when multiple values arrive', () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // Emit after a small delay to ensure subscription is established
    setTimeout(() => {
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
      source$.next({ climateEntityId: 'gymnasium', temperature: 15 });
      source$.next({ climateEntityId: 'hall', temperature: 17 });
      source$.next({ climateEntityId: 'lounge', temperature: 19 });
      source$.next({ climateEntityId: 'office', temperature: 20 });
    }, 10);

    return pipe(
      replayed$,
      observableToStream,
      Stream.take(5),
      Stream.runCollect,
      Effect.map(Array.fromIterable),
      Effect.flatMap((arr) => assertLength(arr, 5)),
      Effect.flatMap((arr) => assertUniqueKeys(arr, 5)),
    );
  });

  it.effect('does not emit duplicate values for same key', () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // Emit after a small delay to ensure subscription is established
    setTimeout(() => {
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    }, 10);

    return pipe(
      replayed$,
      observableToStream,
      Stream.take(1),
      Stream.runCollect,
      Effect.map(Array.fromIterable),
      Effect.flatMap((arr) => assertLength(arr, 1)),
    );
  });

  it.effect('emits when value changes for existing key', () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // Emit after a small delay to ensure subscription is established
    setTimeout(() => {
      source$.next({ climateEntityId: 'bedroom', temperature: 18 });
      source$.next({ climateEntityId: 'office', temperature: 20 });
      source$.next({ climateEntityId: 'bedroom', temperature: 22 });
    }, 10);

    return pipe(
      replayed$,
      observableToStream,
      Stream.take(3),
      Stream.runCollect,
      Effect.map(Array.fromIterable),
      Effect.flatMap((arr) => assertLength(arr, 3)),
      Effect.flatMap((arr) => assertLastValue(arr, 'bedroom', 22)),
    );
  });
});
