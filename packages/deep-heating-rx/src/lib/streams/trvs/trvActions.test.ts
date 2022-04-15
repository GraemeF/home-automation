import { determineAction } from "./trvActions";
import { DateTime } from "luxon";

describe("TRV action", () => {
  const daytime: DateTime = DateTime.fromISO("2020-01-01T12:00Z");
  const trvId = "the trv";

  it("OFF", () => {
    const action = determineAction(
      { trvId, targetTemperature: 20 },
      { trvId, mode: "OFF", source: "Hive", targetTemperature: 7 },
      {
        trvId,
        temperatureReading: { time: daytime, temperature: 10 },
      },
      { trvId, scheduledTargetTemperature: 18 }
    );

    expect(action).toBeNull();
  });

  it("should do something", () => {
    const action = determineAction(
      {
        targetTemperature: 23,
        trvId: trvId,
      },
      {
        trvId: trvId,
        mode: "MANUAL",
        targetTemperature: 18.5,
        source: "Hive",
      },
      {
        trvId: trvId,
        temperatureReading: {
          temperature: 21,
          time: daytime,
        },
      },
      {
        trvId: trvId,
        scheduledTargetTemperature: 18,
      }
    );

    expect(action).toStrictEqual({
      mode: "MANUAL",
      targetTemperature: 23,
      trvId: trvId,
    });
  });

  it("should change from MANUAL to SCHEDULE", () => {
    const action = determineAction(
      {
        targetTemperature: 23,
        trvId: trvId,
      },
      {
        trvId: trvId,
        mode: "MANUAL",
        targetTemperature: 18.5,
        source: "Hive",
      },
      {
        trvId: trvId,
        temperatureReading: {
          temperature: 18.5,
          time: daytime,
        },
      },
      {
        trvId: trvId,
        scheduledTargetTemperature: 23,
      }
    );

    expect(action).toStrictEqual({
      mode: "SCHEDULE",
      trvId: trvId,
    });
  });

  it("should change from SCHEDULE to MANUAL", () => {
    const action = determineAction(
      {
        targetTemperature: 18.5,
        trvId: trvId,
      },
      {
        trvId: trvId,
        mode: "SCHEDULE",
        targetTemperature: 23,
        source: "Hive",
      },
      {
        trvId: trvId,
        temperatureReading: {
          temperature: 18.5,
          time: daytime,
        },
      },
      {
        trvId: trvId,
        scheduledTargetTemperature: 23,
      }
    );

    expect(action).toStrictEqual({
      mode: "MANUAL",
      targetTemperature: 18.5,
      trvId: trvId,
    });
  });

  it("should change MANUAL target temperature", () => {
    const action = determineAction(
      {
        targetTemperature: 18.5,
        trvId: trvId,
      },
      {
        trvId: trvId,
        mode: "MANUAL",
        targetTemperature: 23,
        source: "Hive",
      },
      {
        trvId: trvId,
        temperatureReading: {
          temperature: 18.5,
          time: daytime,
        },
      },
      {
        trvId: trvId,
        scheduledTargetTemperature: 23,
      }
    );

    expect(action).toStrictEqual({
      mode: "MANUAL",
      targetTemperature: 18.5,
      trvId: trvId,
    });
  });
});
