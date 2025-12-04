import { describe, expect, it } from '@codeforbreakfast/bun-test-effect';
import { Array, Effect, Option, pipe, Stream } from 'effect';
import { Subject } from 'rxjs';
import { observableToStream } from './adapters';
import { shareReplayLatestDistinctByKey } from './rxx';

interface TrvTemperature {
  readonly climateEntityId: string;
  readonly temperature: number;
}

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
        Effect.map((arr) => {
          expect(arr).toHaveLength(3);
          expect(arr.map((v) => v.climateEntityId).sort()).toEqual([
            'bedroom',
            'lounge',
            'office',
          ]);
        }),
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
      Effect.map((arr) => {
        expect(arr).toHaveLength(5);
        expect(new Set(arr.map((v) => v.climateEntityId)).size).toBe(5);
      }),
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
      Effect.map((arr) => {
        expect(arr).toHaveLength(1);
      }),
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
      Effect.tap((arr) => {
        expect(arr).toHaveLength(3);
      }),
      Effect.map(Array.last),
      Effect.map(Option.getOrThrow),
      Effect.map((lastValue) => {
        expect(lastValue.climateEntityId).toBe('bedroom');
        expect(lastValue.temperature).toBe(22);
      }),
    );
  });
});
