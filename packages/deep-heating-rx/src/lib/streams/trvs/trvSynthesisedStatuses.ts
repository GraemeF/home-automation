import {
  ClimateEntityId,
  ClimateEntityStatus,
  ClimateTemperatureReading,
  TrvControlState,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinct } from '@home-automation/rxx';
import { Observable, combineLatest } from 'rxjs';
import { filter, map, mergeAll, mergeMap } from 'rxjs/operators';

export const getTrvSynthesisedStatuses = (
  trvIds$: Observable<ClimateEntityId[]>,
  trvTemperatures$: Observable<ClimateTemperatureReading>,
  trvControlStates$: Observable<TrvControlState>
): Observable<ClimateEntityStatus> =>
  trvIds$.pipe(
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
