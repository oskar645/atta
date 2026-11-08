const Duration _moscowUtcOffset = Duration(hours: 3);

/// Converts a calendar date selected in the UI to the start of that date in
/// Europe/Moscow, independently of the device timezone.
DateTime moscowDateStartUtc(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day)
      .subtract(_moscowUtcOffset);
}

/// Inclusive end of a calendar date in Europe/Moscow.
DateTime moscowDateEndUtc(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day + 1)
      .subtract(_moscowUtcOffset)
      .subtract(const Duration(microseconds: 1));
}
