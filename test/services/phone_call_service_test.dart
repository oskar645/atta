import 'package:atta/src/services/listings_service.dart';
import 'package:atta/src/services/phone_call_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('direct calls use one normalized tel uri', () async {
    Uri? openedUri;
    LaunchMode? openedMode;
    final service = PhoneCallService(
      launcher: (uri, mode) async {
        openedUri = uri;
        openedMode = mode;
        return true;
      },
    );

    final result = await service.openNumber('+7 (928) 123-45-67');

    expect(result.opened, isTrue);
    expect(openedUri.toString(), 'tel:+79281234567');
    expect(openedMode, LaunchMode.externalApplication);
  });

  test('listing calls resolve the exact listing before opening dialer',
      () async {
    final listings = _CallListingsService('79281234567');
    Uri? openedUri;
    final service = PhoneCallService(
      launcher: (uri, mode) async {
        openedUri = uri;
        return true;
      },
    );

    final result = await service.callListing(
      listings: listings,
      listingId: 'listing-42',
    );

    expect(result.opened, isTrue);
    expect(listings.requestedIds, <String>['listing-42']);
    expect(openedUri.toString(), 'tel:+79281234567');
  });

  test('missing listing contact never opens a wrong number', () async {
    final listings = _CallListingsService('');
    var launchCount = 0;
    final service = PhoneCallService(
      launcher: (uri, mode) async {
        launchCount += 1;
        return true;
      },
    );

    final result = await service.callListing(
      listings: listings,
      listingId: 'old-listing',
    );

    expect(result.failure, PhoneCallFailure.unavailable);
    expect(launchCount, 0);
  });

  test('seller profile calls resolve the unique active listing contact',
      () async {
    final listings = _CallListingsService('79281234567');
    Uri? openedUri;
    final service = PhoneCallService(
      launcher: (uri, mode) async {
        openedUri = uri;
        return true;
      },
    );

    final result = await service.callSeller(
      listings: listings,
      sellerId: 'seller-42',
    );

    expect(result.opened, isTrue);
    expect(listings.requestedSellerIds, <String>['seller-42']);
    expect(openedUri.toString(), 'tel:+79281234567');
  });
}

class _CallListingsService extends ListingsService {
  _CallListingsService(this.phone);

  final String phone;
  final List<String> requestedIds = <String>[];
  final List<String> requestedSellerIds = <String>[];

  @override
  Future<String> getCallContact(String listingId) async {
    requestedIds.add(listingId);
    return phone;
  }

  @override
  Future<String> getOwnerCallContact(String ownerId) async {
    requestedSellerIds.add(ownerId);
    return phone;
  }
}
