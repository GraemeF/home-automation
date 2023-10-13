import {
  ClimateEntityId,
  ClimateTemperatureReading,
  TrvControlState,
  TrvStatus,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeAll, mergeMap } from 'rxjs/operators';

export function getTrvSynthesisedStatuses(
  trvIds$: Observable<ClimateEntityId[]>,
  trvTemperatures$: Observable<ClimateTemperatureReading>,
  trvControlStates$: Observable<TrvControlState>
): Observable<TrvStatus> {
  return trvIds$.pipe(
    mergeMap((trvIds) =>
      trvIds.map((trvId) =>
        combineLatest([
          trvTemperatures$.pipe(filter((x) => x.climateEntityId === trvId)),
          trvControlStates$.pipe(filter((x) => x.climateEntityId === trvId)),
        ]).pipe(
          map(([trvTemperature, trvControlState]) => ({
            climateEntityId: trvId,
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
