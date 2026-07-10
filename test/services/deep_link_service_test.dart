import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('atta://listing/{id} parses as listing deep link', () {
    final link = parseAttaDeepLink(
      Uri.parse('atta://listing/8b22bde6-a806-4989-bb37-ef1b550ca853'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.listing);
    expect(link?.listingId, '8b22bde6-a806-4989-bb37-ef1b550ca853');
  });

  test('atta://invite?ref={referralCode} parses as invite deep link', () {
    final link = parseAttaDeepLink(
      Uri.parse('atta://invite?ref=REFERRAL_CODE_123'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.invite);
    expect(link?.referrerId, 'REFERRAL_CODE_123');
  });

  test('https://attamarket.online/listing/{id} parses as listing deep link',
      () {
    final link = parseAttaDeepLink(
      Uri.parse(
          'https://attamarket.online/listing/8b22bde6-a806-4989-bb37-ef1b550ca853'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.listing);
    expect(link?.listingId, '8b22bde6-a806-4989-bb37-ef1b550ca853');
  });

  test('https://www.attamarket.online/listing/{id} also parses', () {
    final link = parseAttaDeepLink(
      Uri.parse('https://www.attamarket.online/listing/listing-55'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.listing);
    expect(link?.listingId, 'listing-55');
  });

  test('https://attamarket.online/app?ref={code} parses as invite deep link',
      () {
    final link = parseAttaDeepLink(
      Uri.parse('https://attamarket.online/app?ref=REFERRAL_CODE_456'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.invite);
    expect(link?.referrerId, 'REFERRAL_CODE_456');
  });

  test('saving pending listing deep link does not log out user', () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(uid: 'user-1'),
    );
    final service = DeepLinkService();

    await service.savePendingListingId('listing-1');

    expect(await service.readPendingListingId(), 'listing-1');
    expect((await tokenStorage.readCurrentUser())?.uid, 'user-1');
  });

  test('pending listing deep link is stored for unauthorized user', () async {
    final service = DeepLinkService();

    await service.savePendingListingId('listing-42');

    expect(await service.readPendingListingId(), 'listing-42');
  });

  test('pending listing deep link is consumed after login', () async {
    final service = DeepLinkService();
    await service.savePendingListingId('listing-77');

    final pending = await service.consumePendingListingId();

    expect(pending, 'listing-77');
    expect(await service.readPendingListingId(), isNull);
  });

  test('pending listing deep link clears only for matching listing id',
      () async {
    final service = DeepLinkService();
    await service.savePendingListingId('listing-88');

    await service.clearPendingListingIdIfMatches('listing-99');
    expect(await service.readPendingListingId(), 'listing-88');

    await service.clearPendingListingIdIfMatches('listing-88');
    expect(await service.readPendingListingId(), isNull);
  });

  test('pending invite referral code is stored and cleared', () async {
    final service = DeepLinkService();

    await service.savePendingInviteReferrerId('REFERRAL_CODE_789');
    expect(await service.readPendingInviteReferrerId(), 'REFERRAL_CODE_789');

    await service.clearPendingInviteReferrerId();
    expect(await service.readPendingInviteReferrerId(), isNull);
  });
}
