# Deep Heating

![Supports amd64 Architecture][amd64-shield]
![Supports armv6 Architecture][armv6-shield]
![Supports armv7 Architecture][armv7-shield]

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
[armv6-shield]: https://img.shields.io/badge/armv6-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
