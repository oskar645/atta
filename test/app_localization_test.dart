import 'package:atta/src/app.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app localization is configured for russian', () {
    expect(attaDefaultLocale, const Locale('ru', 'RU'));
    expect(attaSupportedLocales, contains(const Locale('ru', 'RU')));
    expect(
      attaLocalizationsDelegates,
      contains(GlobalMaterialLocalizations.delegate),
    );
    expect(
      attaLocalizationsDelegates,
      contains(GlobalWidgetsLocalizations.delegate),
    );
    expect(
      attaLocalizationsDelegates,
      contains(GlobalCupertinoLocalizations.delegate),
    );
  });
}
