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

## Configuration

A single JSON file configures your home:

## Development

This monorepo was generated using [Nx](https://nx.dev). See
[their docs](https://nx.dev/using-nx/nx-cli) for details about how to add
libraries, run tests, and so on.
