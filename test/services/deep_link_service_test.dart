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

  test('atta://invite?ref={userId} parses as invite deep link', () {
    final link = parseAttaDeepLink(
      Uri.parse('atta://invite?ref=99e19e73-29da-4b0a-87da-21c3f10d82a0'),
    );

    expect(link, isNotNull);
    expect(link?.type, AttaDeepLinkType.invite);
    expect(link?.referrerId, '99e19e73-29da-4b0a-87da-21c3f10d82a0');
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
}
