import { filter, groupBy, map, mergeMap } from 'rxjs/operators';
import { combineLatest, Observable } from 'rxjs';
import { RoomHiveHeatingSchedule } from './hive';
import {
  RoomTrvs,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';

function trvScheduleRooms(roomTrvs$: Observable<RoomTrvs>) {
  return roomTrvs$.pipe(
    map((x) => ({
      roomName: x.roomName,
      scheduleTrvId: x.trvIds.length > 0 ? x.trvIds[0] : null,
    })),
    filter((x) => x.scheduleTrvId !== null),
    groupBy((x) => x.scheduleTrvId)
  );
}

export function getRoomHiveHeatingSchedules(
  roomTrvs$: Observable<RoomTrvs>,
  trvSchedules: Observable<TrvWeekHeatingSchedule>
): Observable<RoomHiveHeatingSchedule> {
  return trvScheduleRooms(roomTrvs$).pipe(
    mergeMap((groupedTrvScheduleRooms) =>
      combineLatest([
        groupedTrvScheduleRooms,
        trvSchedules.pipe(
          filter((y) => y.trvId === groupedTrvScheduleRooms.key)
        ),
      ]).pipe(map(([{ roomName }, { schedule }]) => ({ roomName, schedule })))
    )
  );
}
