import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/reports_api.dart';
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
    final service = ReportsService(api: api);

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
}

class _FakeReportsApi extends ReportsApi {
  _FakeReportsApi() : super(ApiClient(tokenStorage: TokenStorage()));

  String? createdListingId;
  String? resolvedReportId;
  String? rejectedReportId;

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
}
