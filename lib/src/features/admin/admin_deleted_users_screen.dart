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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context
          .read<AdminService>()
          .deletedUsers(period: period, limit: 100);
      if (!mounted) return;
      setState(() {
        total = result['total'] is num
            ? (result['total'] as num).toInt()
            : int.tryParse('${result['total']}') ?? 0;
        items = (result['items'] as List? ?? const [])
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
                                padding: const EdgeInsets.all(12),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
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
