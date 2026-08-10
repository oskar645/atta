import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/api/reports_api.dart';
import 'package:atta/src/services/api/support_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/reports_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('reportListing and closeReportDecision use Timeweb reports api',
      () async {
    final api = _FakeReportsApi();
    final service = ReportsService(
      api: api,
      supportApi: _FakeSupportApi(),
      adminApi: _FakeAdminApi(),
    );

    await service.reportListing(
      listingId: 'listing-1',
      listingOwnerId: 'seller-1',
      reporterId: 'user-1',
      reason: 'Spam',
      comment: 'Bad listing',
    );
    await service.closeReportDecision(
      reportId: 'report-1',
      adminUid: 'admin-1',
      decision: 'resolved',
      adminComment: 'Handled',
    );

    expect(api.createdListingId, 'listing-1');
    expect(api.resolvedReportId, 'report-1');
    expect(api.rejectedReportId, isNull);
  });

  test(
      'streamProcessedReports keeps history and reopenReport returns item to open',
      () async {
    final api = _FakeReportsApi.withItems(<Map<String, dynamic>>[
      <String, dynamic>{'id': 'open-1', 'status': 'open'},
      <String, dynamic>{'id': 'resolved-1', 'status': 'resolved'},
    ]);
    final service = ReportsService(
      api: api,
      supportApi: _FakeSupportApi(),
      adminApi: _FakeAdminApi(),
    );

    await service.refreshReports(force: true);
    final processed = await service.streamProcessedReports().first;
    expect(processed.single['id'], 'resolved-1');

    await service.reopenReport('resolved-1');

    final openReports = await service.streamOpenReports().first;
    expect(
      openReports.map((item) => item['id']),
      containsAll(<String>['open-1', 'resolved-1']),
    );
  });

  test('hideReport removes item from admin cache immediately', () async {
    final api = _FakeReportsApi.withItems(<Map<String, dynamic>>[
      <String, dynamic>{'id': 'open-1', 'status': 'open'},
      <String, dynamic>{'id': 'open-2', 'status': 'open'},
    ]);
    final service = ReportsService(
      api: api,
      supportApi: _FakeSupportApi(),
      adminApi: _FakeAdminApi(),
    );

    await service.refreshReports(force: true);
    await service.hideReport('open-1');

    final openReports = await service.streamOpenReports().first;
    expect(openReports.map((item) => item['id']), isNot(contains('open-1')));
    expect(openReports.map((item) => item['id']), contains('open-2'));
  });
}

class _FakeReportsApi extends ReportsApi {
  _FakeReportsApi()
      : _items = const <Map<String, dynamic>>[],
        super(ApiClient(tokenStorage: TokenStorage()));

  _FakeReportsApi.withItems(List<Map<String, dynamic>> items)
      : _items = items,
        super(ApiClient(tokenStorage: TokenStorage()));

  String? createdListingId;
  String? resolvedReportId;
  String? rejectedReportId;
  String? reopenedReportId;
  String? hiddenReportId;
  final List<Map<String, dynamic>> _items;

  @override
  Future<Map<String, dynamic>> create({
    required String listingId,
    required String listingOwnerId,
    required String reason,
    required String comment,
  }) async {
    createdListingId = listingId;
    return <String, dynamic>{
      'item': <String, dynamic>{'id': 'report-1'}
    };
  }

  @override
  Future<Map<String, dynamic>> listAdmin({int? limit, String? cursor}) async {
    return <String, dynamic>{
      'items': _items,
    };
  }

  @override
  Future<Map<String, dynamic>> resolve(
    String reportId, {
    String? comment,
  }) async {
    resolvedReportId = reportId;
    return <String, dynamic>{
      'item': <String, dynamic>{'id': reportId}
    };
  }

  @override
  Future<Map<String, dynamic>> reject(
    String reportId, {
    String? comment,
  }) async {
    rejectedReportId = reportId;
    return <String, dynamic>{
      'item': <String, dynamic>{'id': reportId}
    };
  }

  @override
  Future<Map<String, dynamic>> reopen(String reportId) async {
    reopenedReportId = reportId;
    return <String, dynamic>{
      'item': <String, dynamic>{'id': reportId, 'status': 'open'}
    };
  }

  @override
  Future<Map<String, dynamic>> hide(String reportId) async {
    hiddenReportId = reportId;
    return <String, dynamic>{
      'item': <String, dynamic>{'id': reportId, 'status': 'hidden'}
    };
  }
}

class _FakeSupportApi extends SupportApi {
  _FakeSupportApi() : super(ApiClient(tokenStorage: TokenStorage()));
}

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(ApiClient(tokenStorage: TokenStorage()));
}
