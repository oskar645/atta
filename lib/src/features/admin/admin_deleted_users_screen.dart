import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminDeletedUsersScreen extends StatefulWidget {
  const AdminDeletedUsersScreen({super.key});
  @override
  State<AdminDeletedUsersScreen> createState() =>
      _AdminDeletedUsersScreenState();
}

class _AdminDeletedUsersScreenState extends State<AdminDeletedUsersScreen> {
  final _scroll = ScrollController();
  String? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  int _generation = 0;
  static const periods = {
    'today': 'Сегодня',
    '7d': '7 дней',
    'month': 'Этот месяц',
    'all': 'Всё время'
  };
  String period = 'all';
  bool loading = true;
  String? error;
  int total = 0;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      loading = true;
      error = null;
      _cursor = null;
      _hasMore = false;
      _loadingMore = false;
    });
    try {
      final result = await context
          .read<AdminService>()
          .deletedUsers(period: period, limit: 100);
      if (!mounted || generation != _generation) return;
      setState(() {
        total = result['total'] is num
            ? (result['total'] as num).toInt()
            : int.tryParse('${result['total']}') ?? 0;
        items = (result['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _cursor = result['nextCursor']?.toString();
        _hasMore = result['hasMore'] == true && (_cursor ?? '').isNotEmpty;
        loading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (loading || _loadingMore || !_hasMore || _cursor == null) return;
    final generation = _generation;
    final cursor = _cursor;
    setState(() => _loadingMore = true);
    try {
      final result = await context.read<AdminService>().deletedUsers(
            period: period, limit: 100, cursor: cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        items.addAll((result['items'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item)));
        _cursor = result['nextCursor']?.toString();
        _hasMore = result['hasMore'] == true && (_cursor ?? '').isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Удалённые пользователи')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Text('Удалённые пользователи · ${periods[period]}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16))),
                  Text('$total',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 20))
                ]),
                const SizedBox(height: 10),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                        segments: periods.entries
                            .map((e) => ButtonSegment(
                                value: e.key, label: Text(e.value)))
                            .toList(),
                        selected: {period},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) {
                          setState(() => period = v.first);
                          _load();
                        })),
              ])),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Text('Не удалось загрузить данные.\n$error',
                              textAlign: TextAlign.center))
                      : items.isEmpty
                          ? const Center(
                              child: Text('За выбранный период удалений нет.'))
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                controller: _scroll,
                                padding: const EdgeInsets.all(12),
                                itemCount: items.length + (_loadingMore ? 1 : 0),
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  if (index == items.length) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  final item = items[index];
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    leading: const CircleAvatar(
                                        child: Icon(Icons.person_off_outlined)),
                                    title: Text(
                                        '${item['display_name'] ?? 'Удалённый пользователь'}'),
                                    subtitle: Text(_subtitle(item)),
                                  );
                                },
                              ))),
        ]),
      );
}

String _subtitle(Map<String, dynamic> item) {
  final phone = '${item['phone'] ?? ''}'.trim();
  final raw = '${item['deleted_at'] ?? ''}';
  final date = DateTime.tryParse(raw)?.toLocal();
  final formatted = date == null
      ? raw
      : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '${phone.isEmpty ? 'Телефон удалён' : phone} · $formatted';
}
