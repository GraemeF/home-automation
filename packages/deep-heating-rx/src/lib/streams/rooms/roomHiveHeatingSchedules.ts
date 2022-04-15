import { filter, groupBy, map, mergeMap } from 'rxjs/operators';
import { combineLatest, Observable } from 'rxjs';
import { RoomTrvs } from './roomTrvs';
import { TrvHiveHeatingSchedule } from '../trvs/trvSchedules';
import { RoomHiveHeatingSchedule } from '@home-automation/deep-heating-hive';

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
  trvSchedules: Observable<TrvHiveHeatingSchedule>
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
