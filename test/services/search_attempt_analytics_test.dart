import 'package:atta/src/services/search_attempt_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typing many letters reports only the final settled query', () async {
    final reports = <Map<String, Object>>[];
    final analytics = SearchAttemptAnalytics(
      (
          {required attemptId,
          required query,
          required resultCount,
          required hasRestrictiveFilters}) async {
        reports.add({'id': attemptId, 'query': query, 'count': resultCount});
      },
      settleDelay: const Duration(milliseconds: 10),
      createAttemptId: () => 'attempt-1',
    );
    for (final query in ['а', 'ар', 'арм', 'арматур', 'арматура']) {
      analytics.queryChanged(query);
      analytics.resultReceived(
          query: query, resultCount: 0, hasRestrictiveFilters: false);
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(reports, [containsPair('query', 'арматура')]);
  });

  test('pause then continuation reuses attempt and supersedes on backend',
      () async {
    final reports = <Map<String, Object>>[];
    final analytics = SearchAttemptAnalytics(
      (
          {required attemptId,
          required query,
          required resultCount,
          required hasRestrictiveFilters}) async {
        reports.add({'id': attemptId, 'query': query, 'count': resultCount});
      },
      settleDelay: const Duration(milliseconds: 5),
      createAttemptId: () => 'attempt-1',
    );
    analytics.queryChanged('арматур');
    analytics.resultReceived(
        query: 'арматур', resultCount: 0, hasRestrictiveFilters: false);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    analytics.queryChanged('арматура');
    analytics.resultReceived(
        query: 'арматура', resultCount: 0, hasRestrictiveFilters: false);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(reports.map((x) => x['id']).toSet(), {'attempt-1'});
    expect(reports.last['query'], 'арматура');
  });

  test('stale response is ignored and clearing starts an independent attempt',
      () async {
    final reports = <String>[];
    var id = 0;
    final analytics = SearchAttemptAnalytics(
      (
              {required attemptId,
              required query,
              required resultCount,
              required hasRestrictiveFilters}) async =>
          reports.add('$attemptId:$query:$resultCount'),
      settleDelay: const Duration(milliseconds: 5),
      createAttemptId: () => 'attempt-${++id}',
    );
    analytics.queryChanged('арматур');
    analytics.queryChanged('арматура');
    analytics.resultReceived(
        query: 'арматур', resultCount: 0, hasRestrictiveFilters: false);
    analytics.resultReceived(
        query: 'арматура', resultCount: 2, hasRestrictiveFilters: false);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    analytics.queryChanged('');
    analytics.queryChanged('арматура');
    analytics.resultReceived(
        query: 'арматура', resultCount: 0, hasRestrictiveFilters: true);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(reports, ['attempt-1:арматура:2', 'attempt-2:арматура:0']);
  });
}
