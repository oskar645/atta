import 'package:flutter_test/flutter_test.dart';
import 'package:atta/src/models/listing.dart';

void main() {
  test('legacy owner archived listing with stale moderator can be resubmitted',
      () {
    final listing = _listing(
      status: 'archived',
      rejectionReason: 'Объявление снято с публикации.',
      moderatedBy: 'admin-1',
    );

    expect(listing.isAdminArchived, isFalse);
    expect(listing.canOwnerResubmit, isTrue);
  });

  test('legacy owner archived listing with old reason can be resubmitted', () {
    final listing = _listing(
      status: 'archived',
      rejectionReason: 'Снято владельцем с публикации.',
      moderatedBy: 'admin-1',
    );

    expect(listing.isAdminArchived, isFalse);
    expect(listing.canOwnerResubmit, isTrue);
  });

  test('admin archived listing cannot be resubmitted', () {
    final listing = _listing(
      status: 'archived',
      rejectionReason: 'Объявление снято с публикации администратором.',
      moderatedBy: 'admin-1',
    );

    expect(listing.isAdminArchived, isTrue);
    expect(listing.canOwnerResubmit, isFalse);
  });
}

Listing _listing({
  required String status,
  required String rejectionReason,
  String? moderatedBy,
}) {
  return Listing.fromMap({
    'id': 'listing-1',
    'owner_id': 'owner-1',
    'owner_email': 'owner@example.com',
    'owner_name': 'Owner',
    'title': 'Listing',
    'description': 'Description',
    'category': 'misc',
    'subcategory': '',
    'price': 1000,
    'phone': '',
    'phone_hidden': false,
    'city': 'Грозный',
    'delivery': <String, Object?>{},
    'photo_items': [
      {
        'id': 'photo-1',
        'url': 'https://example.com/photo.jpg',
        'sort_order': 0,
      },
    ],
    'status': status,
    'rejection_reason': rejectionReason,
    'moderated_by': moderatedBy,
    'published_at': null,
    'created_at': '2026-07-01T10:00:00.000Z',
    'updated_at': '2026-07-02T10:00:00.000Z',
  });
}
