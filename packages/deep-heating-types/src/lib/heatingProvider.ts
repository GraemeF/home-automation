import { Observable, Subject } from 'rxjs';
import { ClimateAction, HeatingUpdate, TrvUpdate } from './deep-heating-types';

export type HeatingProvider = {
  readonly trvApiUpdates$: Observable<TrvUpdate>;
  readonly heatingApiUpdates$: Observable<HeatingUpdate>;
  readonly heatingActions: Subject<ClimateAction>;
  readonly trvActions: Subject<ClimateAction>;
};
