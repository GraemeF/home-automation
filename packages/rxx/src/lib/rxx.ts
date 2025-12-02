import { isDeepStrictEqual } from 'util';
import { Observable } from 'rxjs';
import {
  distinctUntilChanged,
  groupBy,
  map,
  mergeAll,
  shareReplay,
  tap,
} from 'rxjs/operators';

export function shareReplayLatestDistinctByKey<T>(
  keySelector: (observedValue: T) => unknown,
  distinctThing: (a: T, b: T) => boolean = isDeepStrictEqual,
) {
  return (source: Observable<T>): Observable<T> =>
    source.pipe(
      groupBy(keySelector),
      map(shareReplayLatestDistinct(distinctThing)),
      shareReplay(),
      mergeAll(),
    );
}

export function shareReplayLatestByKey<T>(
  keySelector: (observedValue: T) => unknown,
) {
  return (source: Observable<T>): Observable<T> =>
    source.pipe(
      groupBy(keySelector),
      map(shareReplayLatest()),
      shareReplay(),
      mergeAll(),
    );
}

export function shareReplayLatestDistinct<T>(
  distinctThing: (a: T, b: T) => boolean = isDeepStrictEqual,
) {
  return (source: Observable<T>): Observable<T> =>
    source.pipe(distinctUntilChanged(distinctThing), shareReplay(1));
}

export function shareReplayLatest<T>() {
  return (source: Observable<T>): Observable<T> => source.pipe(shareReplay(1));
}

export function logRoom<T extends { readonly roomName: string }>(
  roomName: string,
  title?: string,
) {
  return (source: Observable<T>): Observable<T> =>
    source.pipe(
      tap((x) => {
        if (x.roomName === roomName)
          console.dir([title, x], { depth: 5, colors: true });
      }),
    );
}

export function logTrv<T extends { readonly trvId: string }>(
  trvId: string,
  title?: string,
) {
  return (source: Observable<T>): Observable<T> =>
    source.pipe(
      tap((x) => {
        if (x.trvId === trvId)
          console.dir([title, x], { depth: 5, colors: true });
      }),
    );
}
