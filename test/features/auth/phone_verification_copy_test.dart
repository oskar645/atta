import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('phone verification screen copy is user-friendly', () async {
    final source = await File(
      'lib/src/features/auth/login_screen.dart',
    ).readAsString();

    expect(source.contains('Dev mode / fake checkId'), isFalse);
    expect(source.contains('fake checkId'), isFalse);
    expect(source.contains('Timeweb backend'), isFalse);
    expect(source.contains('Номер для звонка'), isTrue);
    expect(
      source.contains(
        'Позвоните на указанный номер. Звонок бесплатный, трубку брать не нужно.',
      ),
      isTrue,
    );
    expect(
      source.contains(
        'Подтверждение телефона временно недоступно. Попробуйте позже.',
      ),
      isTrue,
    );
    expect(source.contains("После звонка нажмите «Проверить»."), isFalse);
  });
}
