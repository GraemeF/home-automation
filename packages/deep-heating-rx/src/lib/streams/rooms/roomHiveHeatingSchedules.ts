import {
  RoomClimateEntities,
  RoomWeekHeatingSchedule,
  TrvWeekHeatingSchedule,
} from '@home-automation/deep-heating-types';
import { Observable, combineLatest } from 'rxjs';
import { filter, groupBy, map, mergeMap } from 'rxjs/operators';

const trvScheduleRooms = (roomTrvs$: Observable<RoomClimateEntities>) =>
  roomTrvs$.pipe(
    map((x) => ({
      roomName: x.roomName,
      scheduleTrvId:
        x.climateEntityIds.length > 0 ? x.climateEntityIds[0] : null,
    })),
    filter((x) => x.scheduleTrvId !== null),
    groupBy((x) => x.scheduleTrvId),
  );

export const getRoomHiveHeatingSchedules = (
  roomTrvs$: Observable<RoomClimateEntities>,
  trvSchedules: Observable<TrvWeekHeatingSchedule>,
): Observable<RoomWeekHeatingSchedule> =>
  trvScheduleRooms(roomTrvs$).pipe(
    mergeMap((groupedTrvScheduleRooms) =>
      combineLatest([
        groupedTrvScheduleRooms,
        trvSchedules.pipe(
          filter((y) => y.climateEntityId === groupedTrvScheduleRooms.key),
        ),
      ]).pipe(map(([{ roomName }, { schedule }]) => ({ roomName, schedule }))),
    ),
  );
