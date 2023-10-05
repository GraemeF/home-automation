import { map } from 'rxjs/operators';
import { merge, Observable } from 'rxjs';
import {
  RoomTemperature,
  toHeatingSchedule,
  TrvUpdate,
} from '@home-automation/deep-heating-types';
import { InfluxDB, Point } from '@influxdata/influxdb-client';

export class InfluxDBWriter {
  readonly influxPoints$: Observable<Point>;

  constructor(
    trvApiUpdates$: Observable<TrvUpdate>,
    roomTemperatures$: Observable<RoomTemperature>
  ) {
    this.influxPoints$ = merge(
      trvApiUpdates$.pipe(
        map((trvUpdate) =>
          new Point('temperature')
            .floatField('temperature', trvUpdate.state.temperature.temperature)
            .floatField('targetTemperature', trvUpdate.state.target)
            .floatField(
              'scheduleTargetTemperature',
              toHeatingSchedule(
                trvUpdate.state.schedule,
                trvUpdate.state.temperature.time
              )[0].targetTemperature
            )
            .floatField('heating', trvUpdate.state.isHeating ? 1.0 : 0.0)
            .booleanField('isHeating', trvUpdate.state.isHeating)
            .tag('room', trvUpdate.name)
            .tag('source', 'Hive API')
            .tag('deviceType', trvUpdate.deviceType)
            .tag('deviceId', trvUpdate.trvId)
            .timestamp(trvUpdate.state.temperature.time.toJSDate())
        )
      ),
      roomTemperatures$.pipe(
        map((roomTemperature) =>
          new Point('temperature')
            .floatField(
              'temperature',
              roomTemperature.temperatureReading.temperature
            )
            .tag('room', roomTemperature.roomName)
            .tag('source', 'Hue Bridge')
            .tag('deviceType', 'Hue Motion Sensor')
            .timestamp(roomTemperature.temperatureReading.time.toJSDate())
        )
      )
    );
  }

  public subscribe({
    url,
    token,
    org,
    bucket,
  }: {
    url: string;
    org: string;
    bucket: string;
    token: string;
  }): void {
    const client = new InfluxDB({ url, token });
    const writeApi = client.getWriteApi(org, bucket);

    this.influxPoints$.subscribe((point) => writeApi.writePoint(point));
  }
}
