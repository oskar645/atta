import 'package:atta/src/utils/share_texts.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing share text contains app install url and announcement fields',
      () {
    final result = buildListingShareText(
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
      installUrl: 'https://apps.apple.com/app/id123456789',
    );
    final text = result.text;

    expect(result.errorMessage, isNull);
    expect(text, isNotNull);
    expect(text, contains('Toyota Camry'));
    expect(text, contains('Цена: ${formatPrice(1200000)}'));
    expect(text, contains('Город: Москва'));
    expect(text, contains('https://apps.apple.com/app/id123456789'));
    expect(text, isNot(contains('atta://listing')));
    expect(
      text,
      contains(
        'Открыть ATTA:\nhttps://apps.apple.com/app/id123456789',
      ),
    );
  });

  test('listing share text returns russian error when install url is missing',
      () {
    final result = buildListingShareText(
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
      installUrl: '',
    );

    expect(result.text, isNull);
    expect(
      result.errorMessage,
      'Ссылка на приложение пока не настроена.',
    );
  });

  test('listing share text uses fallback app install url by default', () {
    final result = buildListingShareText(
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
    );

    expect(result.errorMessage, isNull);
    expect(result.text, contains('https://apps.apple.com/search?term=ATTA'));
  });

  test('invite share text contains app install url only', () {
    final result = buildInviteShareText(
      currentUserId: 'user-42',
      installUrl: 'https://apps.apple.com/app/id123456789',
    );
    final text = result.text;

    expect(result.errorMessage, isNull);
    expect(text, isNotNull);
    expect(text, contains('Присоединяйся к ATTA'));
    expect(text, contains('https://apps.apple.com/app/id123456789'));
    expect(text, isNot(contains('atta://invite')));
    expect(
      text,
      contains(
        'Скачать приложение:\nhttps://apps.apple.com/app/id123456789',
      ),
    );
  });
}
