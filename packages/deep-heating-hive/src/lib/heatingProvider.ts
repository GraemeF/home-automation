import {
  HeatingAction,
  HeatingUpdate,
  TrvAction,
  TrvUpdate,
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
import { Observable } from 'rxjs';
import { setHeating, setTrv } from './hive-api';

const log = debug('hive');

export type HeatingProvider = {
  trvApiUpdates$: Observable<TrvUpdate>;
  heatingApiUpdates$: Observable<HeatingUpdate>;
  heatingActionSubject: Subject<HeatingAction>;
  trvActionSubject: Subject<TrvAction>;
};

export const createHiveProvider = () => {
  const hiveApiAccess$ = getHiveApiAccess();
  const hiveProductUpdates$ = getHiveProductUpdates(hiveApiAccess$);
  const trvApiUpdates$ = getTrvApiUpdates(hiveProductUpdates$);
  const heatingApiUpdates$ = getHeatingApiUpdates(hiveProductUpdates$);

  const heatingActionSubject = new Subject<HeatingAction>();
  const trvActionSubject = new Subject<TrvAction>();

  heatingActionSubject
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

  trvActionSubject
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
  return {
    trvActionSubject,
    heatingActionSubject,
    trvApiUpdates$,
    heatingApiUpdates$,
  };
};
