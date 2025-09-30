import {
  HouseModeValue,
  RoomDefinition,
  RoomMode,
  RoomModeValue,
  RoomTrvModes,
  TrvMode,
} from '@home-automation/deep-heating-types';
import { shareReplayLatestDistinctByKey } from '@home-automation/rxx';
import { GroupedObservable, Observable, combineLatest } from 'rxjs';
import { filter, map, mergeMap } from 'rxjs/operators';

const getRoomMode = (
  trvModes: readonly TrvMode[],
  houseMode: HouseModeValue,
): RoomModeValue =>
  trvModes.some((x) => x.mode === 'off') ? 'Off' : houseMode;

export const getRoomModes = (
  rooms$: Observable<GroupedObservable<string, RoomDefinition>>,
  houseModes$: Observable<HouseModeValue>,
  roomTrvModes$: Observable<RoomTrvModes>,
): Observable<RoomMode> =>
  rooms$.pipe(
    mergeMap((roomDefinition$) =>
      combineLatest([
        houseModes$,
        roomTrvModes$.pipe(filter((x) => x.roomName === roomDefinition$.key)),
      ]).pipe(
        map(([houseMode, roomTrvModes]) => ({
          roomName: roomTrvModes.roomName,
          mode: getRoomMode(roomTrvModes.trvModes, houseMode),
        })),
      ),
    ),
    shareReplayLatestDistinctByKey((x) => x.roomName),
  );
