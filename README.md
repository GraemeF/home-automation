# HomeAutomation

This monorepo houses projects that can be used to automate your home.

## Deep Heating

This app was born of frustration with the temperature reported by
[Hive TRVs](https://www.hivehome.com/shop/smart-heating/hive-radiator-valve).
You really can't use a temperature sensor situated a couple of inches from a
radiator to reliably tell you the room temperature. I already had a bunch of
[Hue motion sensors](https://www.philips-hue.com/en-gb/p/hue-motion-sensor/8719514342125),
which also report temperature, and decided to use those to control my heating
too.

The result is a simple web app that works well on mobile devices, allowing you
to control and tweak the desired temperature of each room in your home.

### How do I use it?

For each room, set up your Hive schedule as normal to define the temperatures you would like throughout the week. Deep Heating will use these schedules for your target temperatures.

* Your radiators will be turned off and on as needed to get your Hue sensors to read the scheduled target temperature in each room.
* Radiators will turn on before the sheduled time if necessary, to get the room up to temperature by the time your schedule kicks in. (This is rather crude at the moment, but works for me).
* One of your Hue buttons can be used to switch the heating off at night. Your heating won't turn on again until needed, but never before 7am (because my heating is noisy).

### Why isn't everything configurable?

Because this project was originally tailored for my own home, there are some
things that are not yet configurable. I'll endevour to fix this if there's any
interest :)

## Configuration

A single JSON file configures your home:

```json
{
  "heatingId": "...",
  "sleepSwitchId": "...",
  "rooms": []
}
```

property        | description
----------------|-------------------------------------------------------------
`heatingId`     | The Hive id of the main heating thermostat
`sleepSwitchId` | The Hue id of a button that turns the heating off at bedtime

Add an object in `rooms` for each room with a temperature sensor:

```json
{
  "name": "...",
  "temperatureSensorId": "...",
  "trvControlIds": ["...", "..."]
}
```

property        | description
----------------|-------------------------------------------------------------
`name`     | The name of the room, as you would like it displayed in the app
`temperatureSensorId` | The Hue id of the temperature sensor to use to measure room temperature
`trvControlIds` | Array of Hive ids of the TRV Control devices in the room

## Security

*There isn't any!* This is currently assumed to be hosted on your home network,
if you want to access remotely then use a VPN. Use at your own risk!

## Development

This monorepo was generated using [Nx](https://nx.dev). See
[their docs](https://nx.dev/using-nx/nx-cli) for details about how to add
libraries, run tests, and so on.
