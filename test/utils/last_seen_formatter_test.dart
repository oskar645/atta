import 'package:atta/src/utils/last_seen_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 27, 13, 5);

  test('online user is shown as online', () {
    expect(formatLastSeen(null, true, now: now), 'в сети');
  });

  test('formats today without seconds', () {
    expect(
      formatLastSeen(DateTime(2026, 7, 27, 12, 40), false, now: now),
      'был(а) в сети сегодня в 12:40',
    );
  });

  test('formats yesterday without date', () {
    expect(
      formatLastSeen(DateTime(2026, 7, 26, 21, 15), false, now: now),
      'был(а) в сети вчера в 21:15',
    );
  });

  test('formats current year without year', () {
    expect(
      formatLastSeen(DateTime(2026, 7, 25, 12, 40), false, now: now),
      'был(а) в сети 25 июля в 12:40',
    );
  });

  test('formats another year with year', () {
    expect(
      formatLastSeen(DateTime(2025, 7, 25, 12, 40), false, now: now),
      'был(а) в сети 25 июля 2025 г. в 12:40',
    );
  });

  test('returns empty string for absent last seen', () {
    expect(formatLastSeen(null, false, now: now), '');
  });
}
