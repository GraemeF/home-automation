import {
  HeatingAction,
  HeatingProvider,
  TrvAction,
} from '@home-automation/deep-heating-types';
import { from, Subject } from 'rxjs';
import { getHiveApiAccess, getHiveProductUpdates } from './hive';
import { getTrvApiUpdates } from './trvStates';
import { getHeatingApiUpdates } from './heatingStates';
import debug from 'debug';
import {
  debounceTime,
  groupBy,
  mergeMap,
  withLatestFrom,
} from 'rxjs/operators';
import { setHeating, setTrv } from './hive-api';

const log = debug('hive');

export const createHiveProvider: () => HeatingProvider = () => {
  const hiveApiAccess$ = getHiveApiAccess();

  const heatingActions = new Subject<HeatingAction>();
  const trvActions = new Subject<TrvAction>();

  heatingActions
    .pipe(
      debounceTime(5000),
      withLatestFrom(hiveApiAccess$),
      mergeMap(([action, apiAccess]) =>
        from(
          setHeating(
            apiAccess,
            action.heatingId,
            action.mode,
            action.targetTemperature
          )
        )
      )
    )
    .subscribe((x) =>
      log(
        'Heating',
        x.heatingId,
        x.result.ok ? 'has' : 'has not',
        'been changed to',
        x.mode ?? '',
        x.targetTemperature ?? ''
      )
    );

  trvActions
    .pipe(
      groupBy((x) => x.trvId),
      mergeMap((x) => x.pipe(debounceTime(5000))),
      withLatestFrom(hiveApiAccess$),
      mergeMap(([action, apiAccess]) =>
        from(
          setTrv(apiAccess, action.trvId, action.mode, action.targetTemperature)
        )
      )
    )
    .subscribe((x) =>
      log(
        'TRV',
        x.trvId,
        x.result.ok ? 'has' : 'has not',
        'been changed to',
        x.mode ?? '',
        x.targetTemperature ?? ''
      )
    );

  const hiveProductUpdates$ = getHiveProductUpdates(hiveApiAccess$);

  return {
    trvActions,
    heatingActions,
    trvApiUpdates$: getTrvApiUpdates(hiveProductUpdates$),
    heatingApiUpdates$: getHeatingApiUpdates(hiveProductUpdates$),
  };
};
