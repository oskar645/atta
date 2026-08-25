import 'package:atta/src/services/api/api_client.dart';

class AdminApi {
  const AdminApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> dashboardStats() async {
    final response = await client.get(
      '/admin/dashboard/stats',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> users({
    int? limit,
    String? cursor,
    String? search,
  }) async {
    final response = await client.get(
      '/admin/users',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> userRegistrationStats({int? year}) async {
    final response = await client.get(
      '/admin/users/registration-stats',
      authorized: true,
      queryParameters: {
        if (year != null) 'year': '$year',
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> onlineUsers() async {
    final response = await client.get('/admin/online-users', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> todayVisits() async {
    final response = await client.get('/admin/today-visits', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> userById(String userId) async {
    final response = await client.get('/admin/users/$userId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final response =
        await client.delete('/admin/users/$userId', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> sendSupportMessageToUser({
    required String userId,
    required String message,
    required String idempotencyKey,
  }) async {
    final response = await client.post(
      '/admin/users/${Uri.encodeComponent(userId)}/support-message',
      authorized: true,
      body: {
        'message': message.trim(),
        'idempotencyKey': idempotencyKey.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> blocks({
    String? status,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/blocks',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> blockUser(
    String userId, {
    required String duration,
    required String reason,
    String? internalNote,
    String? listingId,
    String? endsAt,
    bool banPhoneIdentity = false,
  }) async {
    final response = await client.post(
      '/admin/users/$userId/block',
      body: {
        'duration': duration,
        'reason': reason.trim(),
        if (internalNote != null && internalNote.trim().isNotEmpty)
          'internal_note': internalNote.trim(),
        if (listingId != null && listingId.trim().isNotEmpty)
          'listing_id': listingId.trim(),
        if (endsAt != null && endsAt.trim().isNotEmpty)
          'ends_at': endsAt.trim(),
        'ban_phone_identity': banPhoneIdentity,
      },
      authorized: true,
    );
    return _mutationResponseMap(response);
  }

  Future<Map<String, dynamic>> unblock(String blockId, {String? reason}) async {
    final response = await client.post(
      '/admin/blocks/$blockId/unblock',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      authorized: true,
    );
    return _mutationResponseMap(response);
  }

  Future<Map<String, dynamic>> updateBlock(
    String blockId, {
    String? endsAt,
    bool? permanent,
    String? internalNote,
    String? reason,
  }) async {
    final response = await client.patch(
      '/admin/blocks/$blockId',
      body: {
        if (endsAt != null && endsAt.trim().isNotEmpty)
          'ends_at': endsAt.trim(),
        if (permanent != null) 'permanent': permanent,
        if (internalNote != null) 'internal_note': internalNote.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      authorized: true,
    );
    return _mutationResponseMap(response);
  }

  Map<String, dynamic> _mutationResponseMap(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    return <String, dynamic>{'ok': true};
  }

  Future<Map<String, dynamic>> listings({
    String? status,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/listings',
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> approveListing(String listingId) async {
    final response = await client.patch(
      '/admin/listings/$listingId/approve',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> rejectListing(
    String listingId, {
    String? reason,
    String? moderationNote,
  }) async {
    final response = await client.patch(
      '/admin/listings/$listingId/reject',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (moderationNote != null && moderationNote.trim().isNotEmpty)
          'moderation_note': moderationNote.trim(),
      },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> archiveListing(
    String listingId, {
    String? status,
    String? note,
  }) async {
    final response = await client.patch(
      '/admin/listings/$listingId/archive',
      body: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteListing(
    String listingId, {
    String? reason,
    String? moderationNote,
  }) async {
    final response = await client.delete(
      '/admin/listings/$listingId',
      body: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (moderationNote != null && moderationNote.trim().isNotEmpty)
          'moderation_note': moderationNote.trim(),
      },
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reports({int? limit, String? cursor}) async {
    final response = await client.get(
      '/admin/reports',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> support() async {
    final response = await client.get('/admin/support', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> promotions({
    String? status,
    String? type,
    String? userId,
    String? listingId,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/promotions',
      authorized: true,
      queryParameters: {
        if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
        if (listingId != null && listingId.trim().isNotEmpty)
          'listingId': listingId.trim(),
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> promotionsSummary() async {
    final response = await client.get(
      '/admin/promotions/summary',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> cancelPromotion(String promotionId) async {
    final response = await client.patch(
      '/admin/promotions/$promotionId/cancel',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> wallets({int? limit, String? cursor}) async {
    final response = await client.get(
      '/admin/wallets',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> walletTransactions({
    String? type,
    String? reason,
    String? userId,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/wallet-transactions',
      authorized: true,
      queryParameters: {
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> bonusAnalytics({
    String? period,
  }) async {
    final response = await client.get(
      '/admin/analytics/bonuses',
      authorized: true,
      queryParameters: {
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> pointsPurchasesSummary({
    String? from,
    String? to,
    String? search,
  }) async {
    final response = await client.get(
      '/admin/payments/points-purchases/summary',
      authorized: true,
      queryParameters: {
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> pointsPurchases({
    String? from,
    String? to,
    String? search,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/payments/points-purchases',
      authorized: true,
      queryParameters: {
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> referralSummary({
    String? period,
    String? from,
    String? to,
  }) async {
    final response = await client.get(
      '/admin/referrals/summary',
      authorized: true,
      queryParameters: {
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> referrals({
    String? period,
    String? from,
    String? to,
    String? search,
    String? userId,
    int? limit,
    String? cursor,
  }) async {
    final response = await client.get(
      '/admin/referrals',
      authorized: true,
      queryParameters: {
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> userReferrals(
    String userId, {
    String? period,
    String? from,
    String? to,
  }) async {
    final response = await client.get(
      '/admin/users/${Uri.encodeComponent(userId)}/referrals',
      authorized: true,
      queryParameters: {
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
        if (from != null && from.trim().isNotEmpty) 'from': from.trim(),
        if (to != null && to.trim().isNotEmpty) 'to': to.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
