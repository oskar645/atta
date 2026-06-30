import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/showcase_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class ShowcaseService {
  ShowcaseService() : _api = ShowcaseApi(_apiClient);

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);

  final ShowcaseApi _api;
  final Set<String> _impressionsSentThisSession = <String>{};
  int _homeRotationOffset = 0;
  int _homeLoadCount = 0;

  Future<List<ShowcaseItem>> getShowcase() async {
    if (!ApiConfig.useTimewebBackend) return const <ShowcaseItem>[];
    final response = await _api.getShowcase();
    final items = response['items'];
    if (items is! List) return const <ShowcaseItem>[];
    return items
        .whereType<Map>()
        .map(
          (item) => ShowcaseItem.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<List<ShowcaseItem>> getHomeShowcase() async {
    final items = await getShowcase();
    if (items.length <= 1) {
      _homeLoadCount += 1;
      return items;
    }

    if (_homeLoadCount > 0) {
      _homeRotationOffset = (_homeRotationOffset + 3) % items.length;
    } else {
      _homeRotationOffset = _homeRotationOffset % items.length;
    }
    _homeLoadCount += 1;

    if (_homeRotationOffset == 0) {
      return items;
    }

    return <ShowcaseItem>[
      ...items.skip(_homeRotationOffset),
      ...items.take(_homeRotationOffset),
    ];
  }

  Future<void> recordImpression(String promotionId) async {
    if (!ApiConfig.useTimewebBackend) return;
    final id = promotionId.trim();
    if (id.isEmpty || _impressionsSentThisSession.contains(id)) return;
    _impressionsSentThisSession.add(id);
    try {
      await _api.recordImpression(id);
    } catch (_) {
      _impressionsSentThisSession.remove(id);
      rethrow;
    }
  }

  Future<void> recordClick(String promotionId) async {
    if (!ApiConfig.useTimewebBackend) return;
    final id = promotionId.trim();
    if (id.isEmpty) return;
    await _api.recordClick(id);
  }
}
