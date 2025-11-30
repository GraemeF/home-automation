import { DateTime } from 'luxon';

/**
 * Returns the current local DateTime.
 * Use with RxJS map() instead of DateTime.local directly, as timer
 * emits numbers that Luxon would interpret as year arguments.
 */
// eslint-disable-next-line effect/no-eta-expansion -- Wrapper needed: DateTime.local accepts optional args that timer would pass
export const localNow = (): DateTime => DateTime.local();
