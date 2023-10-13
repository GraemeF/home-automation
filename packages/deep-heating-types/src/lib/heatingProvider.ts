import { Observable, Subject } from 'rxjs';
import {
  HeatingAction,
  HeatingUpdate,
  TrvAction,
  TrvUpdate,
} from './deep-heating-types';

export type HeatingProvider = {
  trvApiUpdates$: Observable<TrvUpdate>;
  heatingApiUpdates$: Observable<HeatingUpdate>;
  heatingActions: Subject<HeatingAction>;
  trvActions: Subject<TrvAction>;
};
