import 'dart:async';

import 'package:uuid/uuid.dart';

typedef SearchAttemptReporter = Future<void> Function({
  required String attemptId,
  required String query,
  required int resultCount,
  required bool hasRestrictiveFilters,
});

/// Debounces only anonymous analytics. Marketplace requests remain immediate.
class SearchAttemptAnalytics {
  SearchAttemptAnalytics(
    this._report, {
    this.settleDelay = const Duration(milliseconds: 1000),
    String Function()? createAttemptId,
  }) : _createAttemptId = createAttemptId ?? const Uuid().v4;

  final SearchAttemptReporter _report;
  final Duration settleDelay;
  final String Function() _createAttemptId;
  Timer? _timer;
  String? _attemptId;
  String _currentQuery = '';
  int _generation = 0;

  void queryChanged(String rawQuery) {
    _timer?.cancel();
    _generation++;
    final query = rawQuery.trim();
    if (query.isEmpty) {
      _attemptId = null;
      _currentQuery = '';
      return;
    }
    _attemptId ??= _createAttemptId();
    _currentQuery = query;
  }

  void resultReceived({
    required String query,
    required int resultCount,
    required bool hasRestrictiveFilters,
  }) {
    final settledQuery = query.trim();
    if (settledQuery.isEmpty ||
        settledQuery != _currentQuery ||
        _attemptId == null) {
      return;
    }
    _timer?.cancel();
    final generation = _generation;
    final attemptId = _attemptId!;
    _timer = Timer(settleDelay, () {
      if (generation != _generation || settledQuery != _currentQuery) return;
      unawaited(_report(
        attemptId: attemptId,
        query: settledQuery,
        resultCount: resultCount,
        hasRestrictiveFilters: hasRestrictiveFilters,
      ).catchError((_) {}));
    });
  }

  void dispose() => _timer?.cancel();
}
