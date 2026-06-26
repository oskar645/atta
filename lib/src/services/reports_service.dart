import 'dart:async';

import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/reports_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class ReportsService {
  ReportsService({
    ReportsApi? api,
    NotificationsService? notifications,
  })  : _api = api ?? ReportsApi(_apiClient),
        _notifications = notifications ?? NotificationsService();

  final NotificationsService _notifications;
  final ReportsApi _api;
  final StreamController<List<Map<String, dynamic>>> _openReportsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _openReportsCache = const <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>>? _openReportsInFlight;
  DateTime? _lastOpenReportsFetchAt;

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static const Duration _openReportsTtl = Duration(seconds: 20);

  void _debugSource(String message) {
    if (!kDebugMode || !message.contains('unavailable')) return;
    debugPrint(message);
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> reportListing({
    required String listingId,
    required String listingOwnerId,
    required String reporterId,
    required String reason,
    required String comment,
  }) async {
    _debugSource('Reports source: Timeweb');
    await _api.create(
      listingId: listingId,
      listingOwnerId: listingOwnerId,
      reason: reason,
      comment: comment,
    );
  }

  Stream<List<Map<String, dynamic>>> streamOpenReports() {
    if (_openReportsCache.isEmpty || _isOpenReportsStale()) {
      unawaited(refreshOpenReports(force: _openReportsCache.isEmpty));
    }
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      controller.add(List<Map<String, dynamic>>.from(_openReportsCache));
      final sub = _openReportsController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Future<List<Map<String, dynamic>>> refreshOpenReports({
    bool force = false,
  }) async {
    if (!force && !_isOpenReportsStale() && _openReportsCache.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_openReportsCache);
    }
    final existing = _openReportsInFlight;
    if (existing != null) {
      return existing;
    }
    final future = () async {
      final response = await _api.listAdmin();
      final items = _extractItems(response)
          .where((r) => (r['status'] ?? '').toString() == 'open')
          .toList(growable: false);
      _openReportsCache = items;
      _lastOpenReportsFetchAt = DateTime.now();
      _openReportsController.add(List<Map<String, dynamic>>.from(items));
      return items;
    }();
    _openReportsInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_openReportsInFlight, future)) {
        _openReportsInFlight = null;
      }
    }
  }

  Future<void> closeReportDecision({
    required String reportId,
    required String adminUid,
    required String decision,
    String? adminComment,
  }) async {
    _debugSource('Reports source: Timeweb');
    if (decision == 'rejected' || decision == 'no_violation') {
      await _api.reject(reportId, comment: adminComment);
    } else {
      await _api.resolve(reportId, comment: adminComment);
    }
    _openReportsCache = _openReportsCache
        .where((item) => (item['id'] ?? '').toString() != reportId)
        .toList(growable: false);
    _openReportsController
        .add(List<Map<String, dynamic>>.from(_openReportsCache));
  }

  Future<void> deleteListingById(
    String listingId, {
    String? reason,
  }) async {
    _debugSource('Reports source: Timeweb');
  }

  Future<void> notifyOwnerViaSupport({
    required String ownerUid,
    required String ownerName,
    required String messageFromAdmin,
  }) async {
    _debugSource('Reports source: Timeweb');
  }

  Future<void> notifyOwnerPersonal({
    required String ownerUid,
    required String title,
    required String body,
  }) async {
    await _notifications.sendPersonal(
      userId: ownerUid,
      title: title,
      body: body,
    );
  }

  bool _isOpenReportsStale() {
    final lastFetchAt = _lastOpenReportsFetchAt;
    if (lastFetchAt == null) return true;
    return DateTime.now().difference(lastFetchAt) >= _openReportsTtl;
  }
}
