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

  Future<Map<String, dynamic>> users() async {
    final response = await client.get('/admin/users', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> onlineUsers() async {
    final response = await client.get('/admin/online-users', authorized: true);
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

  Future<Map<String, dynamic>> listings({String? status}) async {
    final response = await client.get(
      '/admin/listings',
      queryParameters: status == null ? null : {'status': status},
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

  Future<Map<String, dynamic>> reports() async {
    final response = await client.get('/admin/reports', authorized: true);
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

  Future<Map<String, dynamic>> wallets() async {
    final response = await client.get('/admin/wallets', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> walletTransactions({
    String? type,
    String? reason,
    String? userId,
  }) async {
    final response = await client.get(
      '/admin/wallet-transactions',
      authorized: true,
      queryParameters: {
        if (type != null && type.trim().isNotEmpty) 'type': type.trim(),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
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
}
