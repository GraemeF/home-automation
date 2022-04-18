const formatter = new Intl.NumberFormat('en-GB', {
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});

export const formatTemperature = (
  temperature?: number,
  showUnits = true
): string =>
  temperature ? formatter.format(temperature) + (showUnits ? 'ºC' : '') : '–';

export const compareByRoomTemperature = (a, b) =>
  (a.temperature?.temperature ?? 999) - (b.temperature?.temperature ?? 999);
