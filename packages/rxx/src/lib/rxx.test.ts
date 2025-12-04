import { describe, expect, it, afterEach } from 'bun:test';
import { Subject, Subscription } from 'rxjs';
import { shareReplayLatestDistinctByKey } from './rxx';

interface TrvTemperature {
  readonly climateEntityId: string;
  readonly temperature: number;
}

describe('shareReplayLatestDistinctByKey', () => {
  // eslint-disable-next-line functional/prefer-readonly-type -- Test subscription tracking
  const subs: Subscription[] = [];

  afterEach(() => {
    subs.forEach((s) => {
      s.unsubscribe();
    });
    subs.length = 0;
  });

  const trackSubscription = (sub: Subscription): void => {
    subs.push(sub);
  };

  it('replays latest value for each key when new subscriber joins', async () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // eslint-disable-next-line functional/prefer-readonly-type -- Test value collection
    const firstValues: TrvTemperature[] = [];
    trackSubscription(
      replayed$.subscribe((v) => {
        firstValues.push(v);
      }),
    );

    source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    source$.next({ climateEntityId: 'office', temperature: 20 });
    source$.next({ climateEntityId: 'lounge', temperature: 19 });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(firstValues).toHaveLength(3);

    // eslint-disable-next-line functional/prefer-readonly-type -- Test value collection
    const lateValues: TrvTemperature[] = [];
    trackSubscription(
      replayed$.subscribe((v) => {
        lateValues.push(v);
      }),
    );

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(lateValues).toHaveLength(3);
    expect(lateValues.map((v) => v.climateEntityId).sort()).toStrictEqual([
      'bedroom',
      'lounge',
      'office',
    ]);
  });

  it('emits all keys when multiple values arrive', async () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // eslint-disable-next-line functional/prefer-readonly-type -- Test value collection
    const values: TrvTemperature[] = [];
    trackSubscription(
      replayed$.subscribe((v) => {
        values.push(v);
      }),
    );

    source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    source$.next({ climateEntityId: 'gymnasium', temperature: 15 });
    source$.next({ climateEntityId: 'hall', temperature: 17 });
    source$.next({ climateEntityId: 'lounge', temperature: 19 });
    source$.next({ climateEntityId: 'office', temperature: 20 });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(values).toHaveLength(5);

    const uniqueKeys = new Set(values.map((v) => v.climateEntityId));
    expect(uniqueKeys.size).toBe(5);
  });

  it('does not emit duplicate values for same key', async () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // eslint-disable-next-line functional/prefer-readonly-type -- Test value collection
    const values: TrvTemperature[] = [];
    trackSubscription(
      replayed$.subscribe((v) => {
        values.push(v);
      }),
    );

    source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    source$.next({ climateEntityId: 'bedroom', temperature: 18 });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(values).toHaveLength(1);
  });

  it('emits when value changes for existing key', async () => {
    const source$ = new Subject<TrvTemperature>();
    const replayed$ = source$.pipe(
      shareReplayLatestDistinctByKey((x) => x.climateEntityId),
    );

    // eslint-disable-next-line functional/prefer-readonly-type -- Test value collection
    const values: TrvTemperature[] = [];
    trackSubscription(
      replayed$.subscribe((v) => {
        values.push(v);
      }),
    );

    source$.next({ climateEntityId: 'bedroom', temperature: 18 });
    source$.next({ climateEntityId: 'office', temperature: 20 });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(values).toHaveLength(2);

    source$.next({ climateEntityId: 'bedroom', temperature: 22 });

    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(values).toHaveLength(3);
    const lastValue = values[values.length - 1];
    expect(lastValue.climateEntityId).toBe('bedroom');
    expect(lastValue.temperature).toBe(22);
  });
});
