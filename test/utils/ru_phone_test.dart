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
      expect(formatRuPhoneForDisplay('79281234567'), '+7 928 123-45-67');
    });
  });
}
