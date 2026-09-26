import 'dart:async';
import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _periods = {
  'today': 'Сегодня',
  '7d': '7 дней',
  'month': 'Этот месяц',
  'all': 'Всё время'
};

class _Header extends StatelessWidget {
  const _Header(this.value, this.changed, {this.trailing});
  final String value;
  final ValueChanged<String> changed;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                    segments: _periods.entries
                        .map((e) =>
                            ButtonSegment(value: e.key, label: Text(e.value)))
                        .toList(),
                    selected: {value},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => changed(v.first)))),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]));
}

abstract class _State<T extends StatefulWidget> extends State<T> {
  String period = 'month';
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];
  Future<Map<String, dynamic>> request();
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await request();
      if (!mounted) return;
      setState(() {
        items = (data['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  void change(String value) {
    if (value == period) return;
    setState(() => period = value);
    unawaited(load());
  }

  Widget result(Widget Function(Map<String, dynamic>) row) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Не удалось загрузить аналитику'),
        TextButton(onPressed: load, child: const Text('Повторить'))
      ]));
    }
    if (items.isEmpty) {
      return const Center(child: Text('За выбранный период данных нет.'));
    }
    return RefreshIndicator(
        onRefresh: load,
        child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => row(items[i])));
  }
}

class AdminZeroResultSearchesScreen extends StatefulWidget {
  const AdminZeroResultSearchesScreen({super.key});
  @override
  State<AdminZeroResultSearchesScreen> createState() => _SearchState();
}

class _SearchState extends _State<AdminZeroResultSearchesScreen> {
  final search = TextEditingController();
  final scroll = ScrollController();
  Timer? timer;
  String? cursor;
  bool hasMore = true;
  bool loadingMore = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 300) unawaited(_loadMore());
    });
    unawaited(load());
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    scroll.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Future<Map<String, dynamic>> request() => context
      .read<AdminService>()
      .zeroResultSearches(period: period, search: search.text, cursor: cursor);

  @override
  Future<void> load() async {
    final requestGeneration = ++generation;
    setState(() {
      loading = true;
      error = null;
      cursor = null;
      hasMore = true;
    });
    try {
      final data = await context
          .read<AdminService>()
          .zeroResultSearches(period: period, search: search.text, limit: 30);
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        items = _analyticsItems(data);
        cursor = data['next_cursor']?.toString();
        hasMore = data['has_more'] == true && (cursor ?? '').isNotEmpty;
        loading = false;
      });
    } catch (e) {
      if (!mounted || requestGeneration != generation) return;
      setState(() {
        error = '$e';
        loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loading || loadingMore || !hasMore || cursor == null) return;
    final requestGeneration = generation;
    final pageCursor = cursor;
    setState(() => loadingMore = true);
    try {
      final data = await context.read<AdminService>().zeroResultSearches(
          period: period, search: search.text, limit: 30, cursor: pageCursor);
      if (!mounted || requestGeneration != generation) return;
      final next = _analyticsItems(data);
      final seen = items.map((x) => '${x['normalized_query']}').toSet();
      setState(() {
        items.addAll(next.where((x) => seen.add('${x['normalized_query']}')));
        cursor = data['next_cursor']?.toString();
        hasMore = data['has_more'] == true && (cursor ?? '').isNotEmpty;
        loadingMore = false;
      });
    } catch (_) {
      if (mounted && requestGeneration == generation) {
        setState(() => loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Поиски без результата')),
      body: Column(children: [
        _Header(period, change),
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
                controller: search,
                decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Поиск по запросам'),
                onChanged: (_) {
                  timer?.cancel();
                  timer = Timer(const Duration(milliseconds: 300), load);
                })),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: TextButton(
                            onPressed: load, child: const Text('Повторить')))
                    : items.isEmpty
                        ? const Center(
                            child: Text('За выбранный период данных нет.'))
                        : RefreshIndicator(
                            onRefresh: load,
                            child: ListView.separated(
                              controller: scroll,
                              padding: const EdgeInsets.all(12),
                              itemCount: items.length + (loadingMore ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                if (i == items.length) {
                                  return const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Center(
                                          child: SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2))));
                                }
                                final x = items[i];
                                return Card(
                                    child: ListTile(
                                  title: Text('${x['query']}'),
                                  subtitle: Text(
                                      'Последний поиск: ${_date(x['last_searched_at'])}'),
                                  trailing: Text('${x['count']}',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800)),
                                ));
                              },
                            ),
                          )),
      ]));
}

List<Map<String, dynamic>> _analyticsItems(Map<String, dynamic> data) =>
    (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

class AdminPopularCategoriesScreen extends StatefulWidget {
  const AdminPopularCategoriesScreen({super.key});
  @override
  State<AdminPopularCategoriesScreen> createState() => _CategoryState();
}

class _CategoryState extends _State<AdminPopularCategoriesScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  Future<Map<String, dynamic>> request() =>
      context.read<AdminService>().popularCategories(period: period);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Популярные категории')),
      body: Column(children: [
        _Header(period, change),
        Expanded(
            child: result((x) => Card(
                child: ListTile(
                    title: Text('${x['category']}'),
                    trailing: Text('${x['views']} просмотров',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)))))),
      ]));
}

class AdminZeroViewListingsScreen extends StatefulWidget {
  const AdminZeroViewListingsScreen({super.key});
  @override
  State<AdminZeroViewListingsScreen> createState() => _ListingsState();
}

class _ListingsState extends _State<AdminZeroViewListingsScreen> {
  String sort = 'oldest';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    period = 'all';
    unawaited(load());
  }

  @override
  Future<Map<String, dynamic>> request() =>
      context.read<AdminService>().zeroViewListings(period: period, sort: sort);
  Future<void> action(String a, Map<String, dynamic> x) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final s = context.read<AdminService>(), id = '${x['id']}';
      if (a == 'approve') await s.approveListing(id);
      if (a == 'reject') {
        await s.rejectListing(id, reason: 'Отклонено администратором');
      }
      if (a == 'delete') {
        await s.deleteListing(id, reason: 'Удалено администратором');
      }
      await load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Объявления без просмотров')),
      body: Column(children: [
        _Header(period, change,
            trailing: DropdownButton<String>(
                value: sort,
                items: const [
                  DropdownMenuItem(value: 'oldest', child: Text('Старые')),
                  DropdownMenuItem(value: 'newest', child: Text('Новые'))
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => sort = v);
                    unawaited(load());
                  }
                })),
        Expanded(child: result(_row)),
      ]));
  Widget _row(Map<String, dynamic> x) {
    final p = x['photos'];
    final photo = p is List && p.isNotEmpty
        ? (p.first is Map ? p.first['url'] : p.first)?.toString()
        : null;
    return Card(
        child: InkWell(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ListingDetailScreen(
                        listingId: '${x['id']}', trackUsageAnalytics: false))),
            child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  SizedBox(
                      width: 58,
                      height: 58,
                      child: photo == null
                          ? const ColoredBox(
                              color: Color(0xffeeeeee),
                              child: Icon(Icons.image_outlined))
                          : MediaPreviewBox(imageUrl: photo, borderRadius: 8)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('${x['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${x['price']} ₽ · ${x['category']}'),
                        Text(
                            '${x['city'] ?? ''} · ${_date(x['created_at'])} · 0 просмотров',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text('${x['status']}',
                            style: Theme.of(context).textTheme.labelSmall)
                      ])),
                  PopupMenuButton<String>(
                      enabled: !busy,
                      onSelected: (v) => action(v, x),
                      itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'approve', child: Text('Одобрить')),
                            PopupMenuItem(
                                value: 'reject', child: Text('Отклонить')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Удалить'))
                          ]),
                ]))));
  }
}

String _date(dynamic raw) {
  final d = DateTime.tryParse('$raw')?.toLocal();
  return d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}
