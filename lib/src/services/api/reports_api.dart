import 'package:atta/src/services/api/api_client.dart';

class ReportsApi {
  const ReportsApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> create({
    required String listingId,
    required String listingOwnerId,
    required String reason,
    required String comment,
  }) async {
    final response = await _client.post(
      '/reports',
      authorized: true,
      body: {
        'listingId': listingId,
        'listingOwnerId': listingOwnerId,
        'reason': reason,
        'comment': comment,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> listAdmin({
    int? limit,
    String? cursor,
    String? status,
    String? reason,
    String? search,
    String? sort,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final response = await _client.get(
      '/admin/reports',
      authorized: true,
      queryParameters: {
        if (limit != null) 'limit': '$limit',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status!.trim(),
        if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
        if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
        if ((sort ?? '').trim().isNotEmpty) 'sort': sort!.trim(),
        if (dateFrom != null) 'dateFrom': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> resolve(
    String reportId, {
    String? comment,
    String? decision,
  }) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/resolve',
      authorized: true,
      body: {
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
        if (decision != null && decision.trim().isNotEmpty)
          'decision': decision.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reject(
    String reportId, {
    String? comment,
    String? decision,
  }) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/reject',
      authorized: true,
      body: {
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment,
        if (decision != null && decision.trim().isNotEmpty)
          'decision': decision.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> startReview(String reportId) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/start',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> reopen(String reportId) async {
    final response = await _client.patch(
      '/admin/reports/$reportId/reopen',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> hide(String reportId) async {
    final response = await _client.delete(
      '/admin/reports/$reportId',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
