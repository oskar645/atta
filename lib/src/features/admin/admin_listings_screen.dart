import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  static const int _pageLimit = 50;

  final ScrollController _scrollController = ScrollController();
  String _status = 'all';
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>>? _items;
  String? _errorText;
  bool _loading = true;
  String? _nextCursor;
  bool _hasMore = true;
  bool _loadingMore = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _future = _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load({
    String? cursor,
    bool append = false,
    int? serial,
  }) async {
    final requestSerial = serial ?? ++_requestSerial;
    try {
      final response = await context.read<AdminService>().listings(
            status: _status,
            limit: _pageLimit,
            cursor: cursor,
            forceRefresh: true,
          );
      if (requestSerial != _requestSerial) {
        return _items ?? const <Map<String, dynamic>>[];
      }
      final raw = response['items'];
      final items = raw is! List
          ? const <Map<String, dynamic>>[]
          : raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
      final nextCursor = (response['nextCursor'] ?? '').toString().trim();
      if (mounted) {
        setState(() {
          _items = append ? _appendDeduped(_items ?? const [], items) : items;
          _nextCursor = nextCursor.isEmpty ? null : nextCursor;
          _hasMore = response['hasMore'] == true || nextCursor.isNotEmpty;
          _loadingMore = false;
          _errorText = null;
          _loading = false;
        });
      }
      return _items ?? items;
    } catch (error) {
      if (mounted) {
        setState(() {
          if (!append) {
            _errorText = 'Не удалось загрузить объявления.\n$error';
          } else {
            _errorText = null;
          }
          _loading = false;
          _loadingMore = false;
        });
      }
      return List<Map<String, dynamic>>.from(
          _items ?? const <Map<String, dynamic>>[]);
    }
  }

  Future<void> _refresh() async {
    final serial = ++_requestSerial;
    setState(() {
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
      _future = _load(serial: serial);
      _errorText = null;
      _loading = _items == null;
    });
    await _future;
  }

  Future<void> _setStatus(String status) async {
    final serial = ++_requestSerial;
    setState(() {
      _status = status;
      _items = null;
      _nextCursor = null;
      _hasMore = true;
      _loadingMore = false;
      _future = _load(serial: serial);
      _errorText = null;
      _loading = true;
    });
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _loadingMore ||
        _busy ||
        _nextCursor == null) {
      return;
    }
    if (_scrollController.position.extentAfter > 700) return;
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    _load(cursor: cursor, append: true, serial: _requestSerial);
  }

  String _id(Map<String, dynamic> item) => (item['id'] ?? '').toString();

  void _removeItemLocally(String listingId) {
    final items = _items;
    if (items == null) return;
    setState(() {
      _items =
          items.where((item) => _id(item) != listingId).toList(growable: false);
    });
  }

  List<Map<String, dynamic>> _appendDeduped(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> next,
  ) {
    final seen = current.map(_id).toSet();
    return <Map<String, dynamic>>[
      ...current,
      ...next.where((item) => seen.add(_id(item))),
    ];
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.approveListing(listingId);
      _removeItemLocally(listingId);
      if (!mounted) return;
      showAppSnack(context, 'Объявление одобрено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка одобрения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.rejectListing(listingId, reason: 'Rejected by admin');
      _removeItemLocally(listingId);
      if (!mounted) return;
      showAppSnack(context, 'Объявление отклонено');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка отклонения: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final adminService = context.read<AdminService>();
    setState(() => _busy = true);
    try {
      final listingId = _id(item);
      await adminService.deleteListing(listingId, reason: 'Deleted by admin');
      _removeItemLocally(listingId);
      if (!mounted) return;
      showAppSnack(context, 'Объявление скрыто');
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка удаления: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Объявления')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                    label: 'Все',
                    value: 'all',
                    current: _status,
                    onSelected: _setStatus),
                _StatusChip(
                    label: 'Активные',
                    value: 'approved',
                    current: _status,
                    onSelected: _setStatus),
                _StatusChip(
                    label: 'Pending',
                    value: 'pending',
                    current: _status,
                    onSelected: _setStatus),
                _StatusChip(
                    label: 'Rejected',
                    value: 'rejected',
                    current: _status,
                    onSelected: _setStatus),
                _StatusChip(
                    label: 'Archived',
                    value: 'archived',
                    current: _status,
                    onSelected: _setStatus),
                _StatusChip(
                    label: 'Deleted',
                    value: 'deleted',
                    current: _status,
                    onSelected: _setStatus),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                final items =
                    _items ?? snap.data ?? const <Map<String, dynamic>>[];
                if (_loading && items.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: const [
                      SkeletonAdminModerationCard(),
                      SkeletonAdminModerationCard(),
                      SkeletonAdminModerationCard(),
                    ],
                  );
                }
                if (_errorText != null && items.isEmpty) {
                  return _AdminListingsStateView(
                    message: _errorText!,
                    onRetry: _refresh,
                  );
                }
                if (items.isEmpty) {
                  return _AdminListingsStateView(
                    message: 'Список объявлений пока пуст.',
                    onRetry: _refresh,
                    showButton: false,
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return _loadingMore
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox(height: 12);
                      }
                      final item = items[index];
                      final status = (item['status'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['title'] ?? 'Без названия').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                  '${(item['price'] ?? 0).toString()} ₽ • ${(item['city'] ?? '').toString()}'),
                              Text(
                                  'Владелец: ${(item['owner_name'] ?? '').toString()}'),
                              Text('Статус: $status'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: _busy || status == 'approved'
                                        ? null
                                        : () => _approve(item),
                                    child: const Text('Одобрить'),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: _busy || status == 'rejected'
                                        ? null
                                        : () => _reject(item),
                                    child: const Text('Отклонить'),
                                  ),
                                  OutlinedButton(
                                    onPressed:
                                        _busy ? null : () => _delete(item),
                                    child: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String current;
  final Future<void> Function(String value) onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: current == value,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _AdminListingsStateView extends StatelessWidget {
  const _AdminListingsStateView({
    required this.message,
    required this.onRetry,
    this.showButton = true,
  });

  final String message;
  final Future<void> Function() onRetry;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (showButton) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
