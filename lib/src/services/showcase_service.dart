import 'package:atta/src/models/showcase_item.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/showcase_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';

class ShowcaseService {
  ShowcaseService({ShowcaseApi? api}) : _api = api ?? ShowcaseApi(_apiClient);

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

  Future<ShowcasePage> getShowcasePage({
    int limit = 20,
    String? cursor,
    String category = 'Все',
    String search = '',
  }) async {
    if (!ApiConfig.useTimewebBackend) {
      return const ShowcasePage(items: <ShowcaseItem>[], hasMore: false);
    }
    final effectiveCategory = category.trim();
    final response = await _api.getShowcase(
      limit: limit,
      cursor: cursor,
      category: effectiveCategory == 'Все' ? null : effectiveCategory,
      search: search.trim(),
    );
    final rawItems = response['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map(
              (item) => ShowcaseItem.fromMap(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList()
        : const <ShowcaseItem>[];
    final nextCursor =
        (response['nextCursor'] ?? response['next_cursor'])?.toString().trim();
    return ShowcasePage(
      items: items,
      hasMore: (response['hasMore'] == true || response['has_more'] == true) &&
          (nextCursor ?? '').isNotEmpty,
      nextCursor: nextCursor,
    );
  }

  Future<List<ShowcaseItem>> getHomeShowcase() async {
    final prepared = prepareHomeShowcase(
      await getShowcase(),
      homeLoadCount: _homeLoadCount,
      rotationOffset: _homeRotationOffset,
    );
    _homeRotationOffset = prepared.nextRotationOffset;
    _homeLoadCount += 1;
    return prepared.items;
  }

  static PreparedHomeShowcase prepareHomeShowcase(
    List<ShowcaseItem> items, {
    required int homeLoadCount,
    required int rotationOffset,
  }) {
    final deduplicated = _deduplicateItems(items);
    if (deduplicated.length <= 1) {
      return PreparedHomeShowcase(
        items: deduplicated,
        nextRotationOffset: rotationOffset,
      );
    }

    deduplicated.sort(_compareShowcaseItemsByFreshness);

    final nextRotationOffset = homeLoadCount > 0
        ? (rotationOffset + 1) % deduplicated.length
        : rotationOffset % deduplicated.length;

    final rotated = <ShowcaseItem>[
      ...deduplicated.skip(nextRotationOffset),
      ...deduplicated.take(nextRotationOffset),
    ];

    return PreparedHomeShowcase(
      items: rotated,
      nextRotationOffset: nextRotationOffset,
    );
  }

  static List<ShowcaseItem> _deduplicateItems(List<ShowcaseItem> items) {
    final seenKeys = <String>{};
    final result = <ShowcaseItem>[];
    for (final item in items) {
      final listingId = item.listingId.trim();
      final promotionId = item.promotionId.trim();
      final dedupeKey = listingId.isNotEmpty
          ? 'listing:$listingId'
          : 'promotion:$promotionId';
      if (dedupeKey.trim().isEmpty || !seenKeys.add(dedupeKey)) {
        continue;
      }
      result.add(item);
    }
    return result;
  }

  static int _compareShowcaseItemsByFreshness(
    ShowcaseItem a,
    ShowcaseItem b,
  ) {
    final startsCompare = _compareNullableDateDesc(a.startsAt, b.startsAt);
    if (startsCompare != 0) return startsCompare;

    final endsCompare = _compareNullableDateDesc(a.endsAt, b.endsAt);
    if (endsCompare != 0) return endsCompare;

    return b.promotionId.compareTo(a.promotionId);
  }

  static int _compareNullableDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
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

class PreparedHomeShowcase {
  const PreparedHomeShowcase({
    required this.items,
    required this.nextRotationOffset,
  });

  final List<ShowcaseItem> items;
  final int nextRotationOffset;
}

class ShowcasePage {
  const ShowcasePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<ShowcaseItem> items;
  final bool hasMore;
  final String? nextCursor;
}
