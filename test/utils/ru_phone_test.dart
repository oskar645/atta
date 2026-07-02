import 'package:atta/src/utils/ru_phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ru phone helpers', () {
    test('normalizes phone to backend format', () {
      expect(normalizeRuPhoneForApi('+7 928 123-45-67'), '79281234567');
      expect(normalizeRuPhoneForApi('8 (928) 123-45-67'), '79281234567');
    });

    test('accepts only 10 local digits', () {
      expect(extractRuPhoneDigits('9281234567123'), '9281234567');
      expect(normalizeRuPhoneForApi('12345'), '');
    });

    test('formats visible field hint style', () {
      expect(formatRuPhoneForField('9281234567'), '928 123-45-67');
      expect(formatRuPhoneForDisplay('79281234567'), '+7 928 123 45 67');
    });

    test('formats russian phones for display with +7', () {
      expect(formatRussianPhone('79288888645'), '+7 928 888 86 45');
      expect(formatRussianPhone('89288888645'), '+7 928 888 86 45');
      expect(formatRussianPhone('+79288888645'), '+7 928 888 86 45');
      expect(formatRussianPhone('9306939954'), '+7 930 693 99 54');
    });

    test('does not fail on empty or incomplete phone', () {
      expect(formatRussianPhone(''), '');
      expect(formatRussianPhone('12345'), '12345');
      expect(formatRussianPhone('+1 202 555 0123'), '+1 202 555 0123');
    });
  });
}
