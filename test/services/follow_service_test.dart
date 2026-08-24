import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/user_follows_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('getFollowedSellers uses Timeweb API', () async {
    final api = _FakeUserFollowsApi(
      items: <Map<String, dynamic>>[
        <String, dynamic>{
          'seller_id': 'seller-1',
          'created_at': '2026-06-18T10:00:00.000Z',
        },
      ],
    );
    final service = FollowService(api: api);

    final items = await service.getFollowedSellers('user-1');

    expect(items.length, 1);
    expect(items.first.sellerId, 'seller-1');
    expect(api.listCalls, 1);
  });

  test('follow and unfollow use Timeweb endpoints', () async {
    final api = _FakeUserFollowsApi(items: const <Map<String, dynamic>>[]);
    final service = FollowService(api: api);

    await service.follow(followerId: 'user-1', sellerId: 'seller-1');
    await service.unfollow(followerId: 'user-1', sellerId: 'seller-1');

    expect(api.followedSellerId, 'seller-1');
    expect(api.unfollowedSellerId, 'seller-1');
  });
}

class _FakeUserFollowsApi extends UserFollowsApi {
  _FakeUserFollowsApi({
    required this.items,
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> items;
  int listCalls = 0;
  String? followedSellerId;
  String? unfollowedSellerId;

  @override
  Future<Map<String, dynamic>> list({int? limit, String? cursor}) async {
    listCalls++;
    return <String, dynamic>{
      'items': items,
    };
  }

  @override
  Future<Map<String, dynamic>> follow(String sellerId) async {
    followedSellerId = sellerId;
    return <String, dynamic>{'followed': true};
  }

  @override
  Future<Map<String, dynamic>> unfollow(String sellerId) async {
    unfollowedSellerId = sellerId;
    return <String, dynamic>{'followed': false};
  }
}
