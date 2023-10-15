import {
  HouseModeValue,
  RoomDefinition,
  RoomMode,
  RoomModeValue,
  RoomTrvModes,
  TrvMode,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { combineLatest, GroupedObservable, Observable } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

function getRoomMode(
  trvModes: TrvMode[],
  houseMode: HouseModeValue
): RoomModeValue {
  return trvModes.some((x) => x.mode === 'off') ? 'Off' : houseMode;
}

export function getRoomModes(
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  houseModes$: Observable<HouseModeValue>,
  roomTrvModes$: Observable<RoomTrvModes>
): Observable<RoomMode> {
  return rooms$.pipe(
    mergeMap((roomDefinition$) =>
      combineLatest([
        houseModes$,
        roomTrvModes$.pipe(filter((x) => x.roomName === roomDefinition$.key)),
      ]).pipe(
        map(([houseMode, roomTrvModes]) => ({
          roomName: roomTrvModes.roomName,
          mode: getRoomMode(roomTrvModes.trvModes, houseMode),
        }))
      )
    ),
    shareReplayLatestDistinctByKey((x) => x.roomName)
  );
}
