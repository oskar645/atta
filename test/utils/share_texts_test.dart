import 'package:atta/src/utils/share_texts.dart';
import 'package:atta/src/utils/price_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listing share text contains public listing url and announcement fields',
      () {
    final result = buildListingShareText(
      listingId: 'listing-42',
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
    );
    final text = result.text;

    expect(result.errorMessage, isNull);
    expect(text, isNotNull);
    expect(text, contains('Toyota Camry'));
    expect(text, contains('Цена: ${formatPrice(1200000)}'));
    expect(text, contains('Город: Москва'));
    expect(text, isNot(contains('atta://listing')));
    expect(text, contains('https://attamarket.online/listing/listing-42'));
    expect(
      text,
      contains(
        'Открыть объявление:\nhttps://attamarket.online/listing/listing-42',
      ),
    );
  });

  test('listing share text returns russian error when listing id is missing',
      () {
    final result = buildListingShareText(
      listingId: '',
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
    );

    expect(result.text, isNull);
    expect(
      result.errorMessage,
      'Ссылка на объявление пока недоступна.',
    );
  });

  test('listing share text uses public listing url by default', () {
    final result = buildListingShareText(
      listingId: 'listing-99',
      title: 'Toyota Camry',
      price: 1200000,
      city: 'Москва',
    );

    expect(result.errorMessage, isNull);
    expect(
        result.text, contains('https://attamarket.online/listing/listing-99'));
  });

  test('listing share text does not include userId referral code or ip', () {
    final result = buildListingShareText(
      listingId: 'listing-123',
      title: 'BMW X5',
      price: 2500000,
      city: 'Казань',
    );
    final text = result.text ?? '';

    expect(text, contains('https://attamarket.online/listing/listing-123'));
    expect(text, isNot(contains('userId')));
    expect(text, isNot(contains('user-1')));
    expect(text, isNot(contains('ref=')));
    expect(text, isNot(contains('referralCode')));
    expect(text, isNot(contains('5.42.125.179')));
    expect(text, isNot(contains('atta://')));
  });

  test('invite share text uses one universal invite link only', () {
    final result = buildInviteShareText(
      referralCode: 'REF-CODE-42',
      installUrl: 'https://attamarket.online/invite',
    );
    final text = result.text;

    expect(result.errorMessage, isNull);
    expect(text, isNotNull);
    expect(text, contains('Привет! Я пользуюсь ATTA'));
    expect(text, contains('https://attamarket.online/invite'));
    expect(text, contains('ref=REF-CODE-42'));
    expect(text, isNot(contains('https://apps.apple.com/search?term=ATTA')));
    expect(text, isNot(contains('5.42.125.179')));
    expect(text, isNot(contains('atta://invite')));
    expect(text, isNot(contains('user-42')));
  });

  test('invite share text without referral code keeps plain invite link', () {
    final result = buildInviteShareText(
      referralCode: '',
      installUrl: 'https://attamarket.online/invite',
    );

    expect(result.errorMessage, isNull);
    expect(result.text, contains('https://attamarket.online/invite'));
    expect(result.text, isNot(contains('ref=')));
  });
}
