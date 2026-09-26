import 'dart:async';

import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key, this.initialStatus = 'all'});
  final String initialStatus;

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  static const _pageLimit = 50;
  static const _statuses = <String, String>{
    'all': 'Все',
    'approved': 'Активные',
    'pending': 'На модерации',
    'rejected': 'Отклонённые',
    'sold': 'Проданные',
    'archived': 'Архивные',
    'deleted': 'Удалённые',
  };
  static const _periods = <String, String>{
    'today': 'Сегодня',
    '7d': '7 дней',
    'month': 'Этот месяц',
    'all': 'Всё время',
  };

  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _searchDebounce;
  late String _status;
  String _period = 'all';
  List<Map<String, dynamic>> _items = [];
  String? _nextCursor;
  String? _error;
  int _total = 0;
  int _serial = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _status = _statuses.containsKey(widget.initialStatus)
        ? widget.initialStatus
        : 'all';
    _scroll.addListener(_maybeLoadMore);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final serial = append ? _serial : ++_serial;
    if (!append) {
      setState(() {
        _loading = true;
        _error = null;
        _nextCursor = null;
      });
    }
    try {
      final response = await context.read<AdminService>().filteredListings(
            status: _status,
            period: _period,
            search: _search.text.trim(),
            limit: _pageLimit,
            cursor: append ? _nextCursor : null,
          );
      if (!mounted || serial != _serial) return;
      final rows = (response['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _items = append ? _dedupe(_items, rows) : rows;
        _total = _asInt(response['total']);
        final cursor = (response['nextCursor'] ?? '').toString().trim();
        _nextCursor = cursor.isEmpty ? null : cursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || serial != _serial) return;
      setState(() {
        _error = 'Не удалось загрузить объявления.\n$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  List<Map<String, dynamic>> _dedupe(
      List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    final ids = a.map((e) => '${e['id']}').toSet();
    return [...a, ...b.where((e) => ids.add('${e['id']}'))];
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _nextCursor == null ||
        _loadingMore ||
        _busy ||
        _scroll.position.extentAfter > 600) {
      return;
    }
    setState(() => _loadingMore = true);
    unawaited(_load(append: true));
  }

  void _changeStatus(String value) {
    if (_status != value) {
      setState(() => _status = value);
      unawaited(_load());
    }
  }

  void _changePeriod(String value) {
    if (_period != value) {
      setState(() => _period = value);
      unawaited(_load());
    }
  }

  void _onSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _action(String action, Map<String, dynamic> item) async {
    if (_busy) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Удалить объявление?'),
                content: Text(
                    '«${item['title'] ?? 'Без названия'}» будет скрыто. Действие выполняется по правилам backend.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Отмена')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Удалить'))
                ],
              ));
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final service = context.read<AdminService>();
      final id = '${item['id']}';
      if (action == 'approve') await service.approveListing(id);
      if (action == 'reject') {
        await service.rejectListing(id, reason: 'Отклонено администратором');
      }
      if (action == 'delete') {
        await service.deleteListing(id, reason: 'Удалено администратором');
      }
      if (!mounted) return;
      showAppSnack(
          context,
          action == 'approve'
              ? 'Объявление одобрено'
              : action == 'reject'
                  ? 'Объявление отклонено'
                  : 'Объявление удалено');
      await _load();
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Действие не выполнено: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Объявления')),
      body: Column(children: [
        Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                            children: _statuses.entries
                                .map((e) => Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: ChoiceChip(
                                          label: Text(e.value),
                                          selected: _status == e.key,
                                          onSelected: (_) =>
                                              _changeStatus(e.key),
                                          visualDensity: VisualDensity.compact),
                                    ))
                                .toList())),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: Text(
                              '${_statuses[_status]} · ${_periods[_period]}',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700))),
                      AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text('$_total',
                              key: ValueKey('$_status:$_period:$_total'),
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900)))
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SegmentedButton<String>(
                                segments: _periods.entries
                                    .map((e) => ButtonSegment(
                                        value: e.key, label: Text(e.value)))
                                    .toList(),
                                selected: {_period},
                                onSelectionChanged: (v) =>
                                    _changePeriod(v.first),
                                showSelectedIcon: false,
                                style: const ButtonStyle(
                                    visualDensity: VisualDensity(
                                        horizontal: -2, vertical: -2)),
                              ))),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 220,
                          child: TextField(
                              controller: _search,
                              onChanged: _onSearch,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  prefixIcon: Icon(Icons.search, size: 20),
                                  hintText: 'Поиск',
                                  border: OutlineInputBorder())))
                    ]),
                  ]),
            )),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(12), children: const [
        SkeletonAdminModerationCard(),
        SkeletonAdminModerationCard(),
        SkeletonAdminModerationCard()
      ]);
    }
    if (_error != null && _items.isEmpty) {
      return _State(message: _error!, retry: _load);
    }
    if (_items.isEmpty) {
      return _State(
          message: 'За выбранный период объявлений нет.',
          retry: _load,
          showButton: false);
    }
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _items.length + (_loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _items.length) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)));
              }
              return _ListingRow(
                  item: _items[index],
                  busy: _busy,
                  onAction: (a) => _action(a, _items[index]));
            }));
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow(
      {required this.item, required this.busy, required this.onAction});
  final Map<String, dynamic> item;
  final bool busy;
  final ValueChanged<String> onAction;

  String? get photo {
    final photoItems = item['photo_items'];
    if (photoItems is List &&
        photoItems.isNotEmpty &&
        photoItems.first is Map) {
      return (photoItems.first['url'] ?? photoItems.first['storage_url'])
          ?.toString();
    }
    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty) {
      return photos.first is Map
          ? photos.first['url']?.toString()
          : photos.first.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = '${item['status'] ?? ''}'.toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    final date = _eventDate(item, status);
    return Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => status == 'deleted'
                ? _DeletedListingDetails(item: item)
                : ListingDetailScreen(
                    listingId: '${item['id']}', trackUsageAnalytics: false),
          )),
          child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                SizedBox(
                    width: 72,
                    height: 72,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: photo == null || photo!.isEmpty
                            ? ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: const Icon(Icons.image_outlined))
                            : MediaPreviewBox(
                                imageUrl: photo!, borderRadius: 0))),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${item['title'] ?? 'Без названия'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('${item['price'] ?? 0} ₽',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(_owner(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 5),
                      Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Badge(status: status),
                            if (date.isNotEmpty)
                              Text(_formatDate(date),
                                  style: TextStyle(
                                      fontSize: 12, color: scheme.outline)),
                          ]),
                    ])),
                PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: 'Действия',
                    onSelected: onAction,
                    itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'approve', child: Text('Одобрить')),
                          PopupMenuItem(
                              value: 'reject', child: Text('Отклонить')),
                          PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'delete', child: Text('Удалить')),
                        ]),
              ])),
        ));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    const labels = {
      'approved': 'Активно',
      'pending': 'На модерации',
      'sold': 'Продано',
      'rejected': 'Отклонено',
      'archived': 'Архив',
      'deleted': 'Удалено'
    };
    final colors = {
      'approved': Colors.green,
      'pending': Colors.orange,
      'sold': Colors.blue,
      'rejected': Colors.red,
      'archived': Colors.blueGrey,
      'deleted': Colors.grey
    };
    final color = colors[status] ?? Colors.grey;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(99)),
        child: Text(labels[status] ?? status,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)));
  }
}

class _DeletedListingDetails extends StatelessWidget {
  const _DeletedListingDetails({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final photos = (item['photo_items'] as List? ?? const [])
        .whereType<Map>()
        .map((photo) => '${photo['url'] ?? ''}')
        .where((url) => url.isNotEmpty)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Удалённое объявление')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (photos.isNotEmpty)
            SizedBox(
              height: 220,
              child: PageView(
                children: photos
                    .map((url) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: MediaPreviewBox(imageUrl: url),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 16),
          Text('${item['title'] ?? 'Без названия'}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('${item['price'] ?? 0} ₽',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const _Badge(status: 'deleted'),
          const SizedBox(height: 16),
          Text('${item['description'] ?? 'Описание отсутствует'}'),
          const SizedBox(height: 16),
          Text('Продавец: ${_owner(item)}'),
          Text('Город: ${item['city'] ?? '—'}'),
          Text('Удалено: ${_formatDate('${item['deleted_at'] ?? ''}')}'),
        ],
      ),
    );
  }
}

class _State extends StatelessWidget {
  const _State(
      {required this.message, required this.retry, this.showButton = true});
  final String message;
  final Future<void> Function() retry;
  final bool showButton;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            if (showButton) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: retry, child: const Text('Повторить'))
            ]
          ])));
}

int _asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _owner(Map<String, dynamic> item) =>
    '${item['owner_name'] ?? item['ownerName'] ?? 'Продавец не указан'}';
String _eventDate(Map<String, dynamic> item, String status) {
  final key = status == 'approved'
      ? 'published_at'
      : status == 'rejected'
          ? 'moderated_at'
          : (status == 'sold' || status == 'archived')
              ? 'archived_at'
              : status == 'deleted'
                  ? 'deleted_at'
                  : 'created_at';
  return '${item[key] ?? ''}';
}

String _formatDate(String raw) {
  final date = DateTime.tryParse(raw)?.toLocal();
  if (date == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year}, ${two(date.hour)}:${two(date.minute)}';
}
