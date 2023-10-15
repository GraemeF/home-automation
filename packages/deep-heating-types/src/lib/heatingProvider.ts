import { Observable, Subject } from 'rxjs';
import { ClimateAction, HeatingUpdate, TrvUpdate } from './deep-heating-types';

export type HeatingProvider = {
  trvApiUpdates$: Observable<TrvUpdate>;
  heatingApiUpdates$: Observable<HeatingUpdate>;
  heatingActions: Subject<ClimateAction>;
  trvActions: Subject<ClimateAction>;
};
