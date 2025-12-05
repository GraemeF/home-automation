# Deep Heating

![Supports amd64 Architecture][amd64-shield]
![Supports arm64 Architecture][arm64-shield]

This app was born of frustration with the temperature reported by
[Hive TRVs](https://www.hivehome.com/shop/smart-heating/hive-radiator-valve).
You really can't use a temperature sensor situated a couple of inches from a
radiator to reliably tell you the room temperature. I already had a bunch of
[Hue motion sensors](https://www.philips-hue.com/en-gb/p/hue-motion-sensor/8719514342125),
which also report temperature, and decided to use those to control my heating
too.

The result is a simple web app that works well on mobile devices, allowing you
to control and tweak the desired temperature of each room in your home.

## How do I use it?

For each room, set up your schedule to define the temperatures you would like
throughout the week. Deep Heating will use these schedules for your target
temperatures.

- Your radiators will be turned off and on as needed to get your temperature
  sensors to read the scheduled target temperature in each room.
- Radiators will turn on before the scheduled time if necessary, to get the room
  up to temperature by the time your schedule kicks in. (This is rather crude at
  the moment, but works for me).
- One of your buttons can be used to switch the heating off at night. Your
  heating won't turn on again until needed, but never before 7am (because my
  heating is noisy).

## TRV Mode Behaviour

Deep Heating respects the HVAC mode set on your TRVs via Home Assistant. The
mode determines how Deep Heating interacts with each valve:

| TRV Mode | Behaviour                                                        |
| -------- | ---------------------------------------------------------------- |
| `off`    | Deep Heating backs off completely - no commands sent to the TRV  |
| `auto`   | Deep Heating defers to the TRV's built-in schedule (e.g. Hive)   |
| `heat`   | Deep Heating takes full control with its own temperature targets |

### Mode Hierarchy

The system uses a layered approach:

1. **House Mode** - Time-based, switches between `Auto` and `Sleeping` (before
   3am or after pressing the goodnight button)
2. **Room Mode** - Derived from the TRVs in the room plus the house mode
3. **TRV Mode** - The actual HVAC mode reported by each device via Home
   Assistant

### Room Mode Logic

If **any TRV in a room is set to `off`**, the entire room switches to `Off`
mode, targeting a minimum temperature of 7°C. This prevents the awkward
situation where one radiator is working overtime to compensate for another
that's been deliberately switched off.

| Room Mode  | Target Temperature                  |
| ---------- | ----------------------------------- |
| `Off`      | 7°C (frost protection)              |
| `Sleeping` | 15°C (energy-saving overnight mode) |
| `Auto`     | Your scheduled temperature          |

### Practical Tips

- **Want to disable a room temporarily?** Set any TRV in that room to `off` via
  Home Assistant. Deep Heating will leave it alone.
- **Using the TRV's built-in schedules?** Leave TRVs in `auto` mode. Deep
  Heating will use the device's internal schedule for target temperatures (e.g.
  Hive schedules).
- **Want Deep Heating in full control?** Set TRVs to `heat` mode. Deep Heating
  will calculate and send temperature targets based on your external sensors.

## Why isn't everything configurable?

Because this project was originally tailored for my own home, there are some
things that are not yet configurable. I'll endeavor to fix this if there's any
interest :)

## Configuration

### Environment variables

| variable name      | description                                                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `SUPERVISOR_URL`   | The URL of your Home Assistant instance, e.g. `http://homeassistant.lan:8123`                                                             |
| `SUPERVISOR_TOKEN` | A [long-lived access token](https://developers.home-assistant.io/docs/auth_api/#long-lived-access-token) for your Home Assistant instance |
| `HOME_CONFIG_PATH` | The path to your home configuration file, e.g. `/config/home.json`                                                                        |

### Home

A single JSON file configures your home:

```json
{
  "heatingId": "...",
  "sleepSwitchId": "...",
  "rooms": []
}
```

| property        | description                                                                            |
| --------------- | -------------------------------------------------------------------------------------- |
| `heatingId`     | The climate entity id of the main heating thermostat                                   |
| `sleepSwitchId` | The event entity of an event (e.g. button press) that turns the heating off at bedtime |

Add an object in `rooms` for each room with a temperature sensor:

```json
{
  "name": "...",
  "temperatureSensorId": "...",
  "climateEntityIds": ["...", "..."],
  "schedule": {
    "monday": {},
    "tuesday": {},
    "wednesday": {},
    "thursday": {},
    "friday": {},
    "saturday": {},
    "sunday": {}
  }
}
```

| property              | description                                                                |
| --------------------- | -------------------------------------------------------------------------- |
| `name`                | The name of the room, as you would like it displayed in the app            |
| `temperatureSensorId` | The entity id of the temperature sensor to use to measure room temperature |
| `climateEntityIds`    | Array of entity ids of the climate control devices in the room             |
| `schedule`            | The schedule of target temperatures for the room                           |

#### Schedule

A schedule defines the target temperatures for a room, for each day of the week. Here's an example:

```json
{
  "monday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "tuesday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "wednesday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "thursday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "friday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "saturday": { "07:00": 18, "17:00": 21, "23:45": 15 },
  "sunday": { "07:00": 18, "17:00": 21, "23:45": 15 }
}
```

## Security

_There isn't any!_ This is currently assumed to be hosted on your home network,
if you want to access remotely then use a VPN. Use at your own risk!

[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[arm64-shield]: https://img.shields.io/badge/arm64-yes-green.svg
