/**
 * Returns YYYY-MM-DD for a timezone using Intl.
 */
export const formatDateInTimezone = (date: Date, timeZone: string): string => {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date)
}
