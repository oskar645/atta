import 'package:atta/src/utils/moscow_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar selection always maps to Moscow day independently of device',
      () {
    final selected = DateTime(2027, 1, 1);

    expect(
      moscowDateStartUtc(selected),
      DateTime.utc(2026, 12, 31, 21),
    );
    expect(
      moscowDateEndUtc(selected),
      DateTime.utc(2027, 1, 1, 20, 59, 59, 999, 999),
    );
  });

  test('month boundary maps to Moscow midnight', () {
    expect(
      moscowDateStartUtc(DateTime(2027, 2, 1)),
      DateTime.utc(2027, 1, 31, 21),
    );
  });
}
