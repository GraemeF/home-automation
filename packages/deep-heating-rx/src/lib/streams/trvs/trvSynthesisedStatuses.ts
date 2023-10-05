import { filter, map, mergeAll, mergeMap } from 'rxjs/operators';
import { combineLatest, Observable } from 'rxjs';
import {
  TrvControlState,
  TrvStatus,
  TrvTemperature,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';

export function getTrvSynthesisedStatuses(
  trvIds$: Observable<string[]>,
  trvTemperatures$: Observable<TrvTemperature>,
  trvControlStates$: Observable<TrvControlState>
): Observable<TrvStatus> {
  return trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        combineLatest([
          trvTemperatures$.pipe(filter((x) => x.trvId === trvId)),
          trvControlStates$.pipe(filter((x) => x.trvId === trvId)),
        ]).pipe(
          map(([trvTemperature, trvControlState]) => ({
            trvId,
            isHeating:
              trvControlState.targetTemperature >
              trvTemperature.temperatureReading.temperature,
          })),
          shareReplayLatestDistinct()
        )
      )
    ),
    mergeAll()
  );
}
