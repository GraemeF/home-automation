export function isNotNull<T>(maybeString: T | null): maybeString is T {
  return maybeString !== null;
}
