import 'dart:async';

import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/notifications_service.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/reports_api.dart';
import 'package:atta/src/services/api/support_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';

class ReportsService {
  ReportsService({
    ReportsApi? api,
    SupportApi? supportApi,
    AdminApi? adminApi,
    NotificationsService? notifications,
  })  : _api = api ?? ReportsApi(_apiClient),
        _supportApi = supportApi ?? SupportApi(_apiClient),
        _adminApi = adminApi ?? AdminApi(_apiClient),
        _notifications = notifications ?? NotificationsService();

  final NotificationsService _notifications;
  final ReportsApi _api;
  final SupportApi _supportApi;
  final AdminApi _adminApi;
  final StreamController<List<Map<String, dynamic>>> _reportsController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  List<Map<String, dynamic>> _reportsCache = const <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>>? _reportsInFlight;
  DateTime? _lastReportsFetchAt;

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static const Duration _reportsTtl = Duration(seconds: 20);

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

  static bool isOpenStatusValue(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'open' ||
        normalized == 'new' ||
        normalized == 'pending' ||
        normalized == 'in_progress';
  }

  static bool isHiddenStatusValue(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'hidden' || normalized == 'deleted';
  }

  List<Map<String, dynamic>> peekAllReports() {
    return List<Map<String, dynamic>>.from(_reportsCache);
  }

  Stream<List<Map<String, dynamic>>> streamOpenReports() {
    return streamReports(openOnly: true);
  }

  Stream<List<Map<String, dynamic>>> streamProcessedReports() {
    return streamReports(openOnly: false);
  }

  Stream<List<Map<String, dynamic>>> streamReports({
    required bool openOnly,
  }) {
    if (_reportsCache.isEmpty || _isReportsStale()) {
      unawaited(refreshReports(force: _reportsCache.isEmpty));
    }
    return Stream<List<Map<String, dynamic>>>.multi((controller) {
      controller.add(_filterReports(openOnly: openOnly));
      final sub = _reportsController.stream.listen(
        (_) => controller.add(_filterReports(openOnly: openOnly)),
        onError: controller.addError,
      );
      controller.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Future<List<Map<String, dynamic>>> refreshOpenReports({
    bool force = false,
  }) =>
      refreshReports(force: force).then(
        (_) => _filterReports(openOnly: true),
      );

  Future<List<Map<String, dynamic>>> refreshReports({
    bool force = false,
  }) async {
    if (!force && !_isReportsStale() && _reportsCache.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_reportsCache);
    }
    final existing = _reportsInFlight;
    if (existing != null) {
      return existing;
    }
    final future = () async {
      final response = await _api.listAdmin();
      final items = _extractItems(response).toList(growable: false);
      _reportsCache = items;
      _lastReportsFetchAt = DateTime.now();
      _reportsController.add(List<Map<String, dynamic>>.from(items));
      return items;
    }();
    _reportsInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_reportsInFlight, future)) {
        _reportsInFlight = null;
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
      final response = await _api.reject(reportId, comment: adminComment);
      _upsertReportFromResponse(response);
    } else {
      final response = await _api.resolve(reportId, comment: adminComment);
      _upsertReportFromResponse(response);
    }
  }

  Future<void> reopenReport(String reportId) async {
    _debugSource('Reports source: Timeweb');
    final response = await _api.reopen(reportId);
    _upsertReportFromResponse(response);
  }

  Future<void> hideReport(String reportId) async {
    _debugSource('Reports source: Timeweb');
    final response = await _api.hide(reportId);
    final item = response['item'];
    final status = item is Map ? (item['status'] ?? '').toString() : 'hidden';
    if (isHiddenStatusValue(status)) {
      _removeReportById(reportId);
      return;
    }
    _upsertReportFromResponse(response);
  }

  Future<void> deleteListingById(
    String listingId, {
    String? reason,
  }) async {
    _debugSource('Reports source: Timeweb');
    await _adminApi.deleteListing(
      listingId,
      reason: reason,
      moderationNote: reason,
    );
  }

  Future<void> notifyOwnerViaSupport({
    required String ownerUid,
    required String ownerName,
    required String messageFromAdmin,
  }) async {
    _debugSource('Reports source: Timeweb');
    await _supportApi.adminContactUser(
      userId: ownerUid,
      name: ownerName,
      subject: 'Обращение поддержки по жалобе',
      text: messageFromAdmin,
    );
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

  Future<Map<String, dynamic>> contactUserViaSupport({
    required String userId,
    required String name,
    required String subject,
    required String message,
  }) {
    return _supportApi.adminContactUser(
      userId: userId,
      name: name,
      subject: subject,
      text: message,
    );
  }

  Map<String, dynamic>? findReportById(String reportId) {
    final normalizedReportId = reportId.trim();
    if (normalizedReportId.isEmpty) return null;
    for (final item in _reportsCache) {
      if ((item['id'] ?? '').toString().trim() == normalizedReportId) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _filterReports({required bool openOnly}) {
    return _reportsCache
        .where((item) {
          if (isHiddenStatusValue((item['status'] ?? '').toString())) {
            return false;
          }
          final isOpen = isOpenStatusValue((item['status'] ?? '').toString());
          return openOnly ? isOpen : !isOpen;
        })
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  void _removeReportById(String reportId) {
    final normalizedReportId = reportId.trim();
    if (normalizedReportId.isEmpty) {
      return;
    }
    _reportsCache = _reportsCache
        .where(
          (entry) =>
              (entry['id'] ?? '').toString().trim() != normalizedReportId,
        )
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
    _reportsController.add(List<Map<String, dynamic>>.from(_reportsCache));
  }

  void _upsertReportFromResponse(Map<String, dynamic> response) {
    final item = response['item'];
    if (item is! Map) {
      return;
    }
    final normalized =
        item.map((key, value) => MapEntry(key.toString(), value));
    final reportId = (normalized['id'] ?? '').toString().trim();
    if (reportId.isEmpty) {
      return;
    }
    final next = _reportsCache
        .where((entry) => (entry['id'] ?? '').toString().trim() != reportId)
        .map(Map<String, dynamic>.from)
        .toList(growable: true);
    next.add(normalized);
    next.sort((a, b) {
      final left = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    _reportsCache = next;
    _reportsController.add(List<Map<String, dynamic>>.from(_reportsCache));
  }

  bool _isReportsStale() {
    final lastFetchAt = _lastReportsFetchAt;
    if (lastFetchAt == null) return true;
    return DateTime.now().difference(lastFetchAt) >= _reportsTtl;
  }
}
