import { Observable, Subject } from 'rxjs';
import { HeatingUpdate, TrvAction, TrvUpdate } from './deep-heating-types';
import { HeatingAction } from './heatingActions';

export type HeatingProvider = {
  trvApiUpdates$: Observable<TrvUpdate>;
  heatingApiUpdates$: Observable<HeatingUpdate>;
  heatingActions: Subject<HeatingAction>;
  trvActions: Subject<TrvAction>;
};
