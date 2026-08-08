import 'package:atta/src/features/listings/listing_detail_screen.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:atta/src/utils/ru_phone.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminBlocksScreen extends StatefulWidget {
  const AdminBlocksScreen({super.key});

  @override
  State<AdminBlocksScreen> createState() => _AdminBlocksScreenState();
}

class _AdminBlocksScreenState extends State<AdminBlocksScreen> {
  static const _filters = <_BlockFilter>[
    _BlockFilter('active', 'Активные'),
    _BlockFilter('temporary', 'Временные'),
    _BlockFilter('permanent', 'Бессрочные'),
    _BlockFilter('finished', 'Завершённые'),
    _BlockFilter('appeals', 'Апелляции'),
    _BlockFilter('history', 'История'),
  ];

  String _status = 'active';
  bool _busy = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  late Future<List<Map<String, dynamic>>> _future = _load(forceRefresh: true);

  Future<List<Map<String, dynamic>>> _load({bool forceRefresh = false}) async {
    final response = await context
        .read<AdminService>()
        .blocks(status: _status, forceRefresh: forceRefresh);
    final raw = response['items'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  Future<void> _refresh() async {
    final next = _load(forceRefresh: true);
    if (!mounted) return;
    setState(() => _future = next);
    await next;
  }

  Future<void> _refreshAfterSuccessfulMutation({
    List<Map<String, dynamic>>? fallbackItems,
  }) async {
    try {
      final items = await _load(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _items = items;
        _future = Future<List<Map<String, dynamic>>>.value(items);
      });
    } catch (_) {
      if (!mounted) return;
      if (fallbackItems != null) {
        setState(() {
          _items = fallbackItems;
          _future = Future<List<Map<String, dynamic>>>.value(fallbackItems);
        });
      }
      showAppSnack(
        context,
        'Действие выполнено, но список не удалось обновить',
        minRepeatGap: Duration.zero,
      );
    }
  }

  void _setFilter(String status) {
    if (_status == status) return;
    setState(() {
      _status = status;
      _future = _load(forceRefresh: true);
    });
  }

  Future<String?> _askText(String title, String label) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _AdminTextDialog(title: title, label: label),
    );
    return result == null || result.trim().isEmpty ? null : result.trim();
  }

  Future<void> _unblock(Map<String, dynamic> item) async {
    final block = _blockValue(item);
    final id = _value(block, const ['id', 'block_id']);
    if (id.isEmpty) return;
    final reason = await _askText('Разблокировать', 'Причина разблокировки');
    if (reason == null || !mounted) return;
    final admin = context.read<AdminService>();
    setState(() => _busy = true);
    try {
      await admin.unblock(id, reason: reason);
      if (!mounted) return;
      showAppSnack(context, 'Пользователь разблокирован');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка разблокировки: $error', isError: true);
      if (mounted) setState(() => _busy = false);
      return;
    }

    await _refreshAfterSuccessfulMutation(
      fallbackItems: _items
          .where((item) =>
              _value(_blockValue(item), const ['id', 'block_id']) != id)
          .toList(growable: false),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _changeDuration(
    Map<String, dynamic> item, {
    required bool permanent,
  }) async {
    final block = _blockValue(item);
    final id = _value(block, const ['id', 'block_id']);
    if (id.isEmpty) return;
    DateTime? endsAt;
    if (!permanent) {
      endsAt = await showDatePicker(
        context: context,
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 3650)),
        initialDate: DateTime.now().add(const Duration(days: 7)),
      );
      if (endsAt == null || !mounted) return;
    }
    final reason = await _askText('Изменить срок', 'Причина изменения');
    if (reason == null || !mounted) return;
    final admin = context.read<AdminService>();

    setState(() => _busy = true);
    try {
      await admin.updateBlock(
        id,
        permanent: permanent,
        endsAt: endsAt?.toIso8601String(),
        reason: reason,
      );
      if (!mounted) return;
      showAppSnack(context, 'Срок блокировки изменён');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка изменения срока: $error', isError: true);
      if (mounted) setState(() => _busy = false);
      return;
    }

    await _refreshAfterSuccessfulMutation();
    if (mounted) setState(() => _busy = false);
  }

  void _openUser(Map<String, dynamic> item) {
    final user = _userValue(item);
    final userId = _value(user.isEmpty ? item : user, const ['id', 'user_id']);
    if (userId.isEmpty) return;
    final avatarUrl = _avatarUrl(
        _value(user, const ['avatar_url', 'photo_url', 'avatarUrl']));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerPublicProfileScreen(
          sellerId: userId,
          initialSellerName: _value(user, const ['display_name', 'name']),
          initialSellerAvatar: avatarUrl,
          initialSellerPhone: _value(user, const ['phone']),
          initialStatusLabel: 'Заблокирован',
          showAdminFields: true,
          titleText: 'Профиль пользователя',
        ),
      ),
    );
  }

  void _openListing(Map<String, dynamic> item) {
    final listing = _listingValue(item);
    final listingId = _value(listing, const ['id']);
    if (listingId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(listingId: listingId),
      ),
    );
  }

  void _openAppeal(Map<String, dynamic> item) {
    final appealId = _value(item, const ['ticket_id', 'id']);
    final message = _value(item, const ['last_message']);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Апелляция'),
        content: SelectableText(
          [
            if (appealId.isNotEmpty) 'Ticket ID: $appealId',
            if (message.isNotEmpty) message,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.label),
                    selected: _status == filter.status,
                    onSelected: (_) => _setFilter(filter.status),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _AdminBlocksState(
                  message:
                      'Не удалось загрузить блокировки.\n${snapshot.error}',
                  onRetry: _refresh,
                );
              }
              final items = snapshot.data ?? const <Map<String, dynamic>>[];
              _items = items;
              if (items.isEmpty) {
                return _AdminBlocksState(
                  message: 'Блокировок в этом фильтре нет.',
                  onRetry: _refresh,
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _BlockCard(
                    item: items[index],
                    busy: _busy,
                    onUnblock: () => _unblock(items[index]),
                    onExtend: () =>
                        _changeDuration(items[index], permanent: false),
                    onPermanent: () =>
                        _changeDuration(items[index], permanent: true),
                    onOpenUser: () => _openUser(items[index]),
                    onOpenListing: () => _openListing(items[index]),
                    onOpenAppeal: () => _openAppeal(items[index]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.item,
    required this.busy,
    required this.onUnblock,
    required this.onExtend,
    required this.onPermanent,
    required this.onOpenUser,
    required this.onOpenListing,
    required this.onOpenAppeal,
  });

  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onUnblock;
  final VoidCallback onExtend;
  final VoidCallback onPermanent;
  final VoidCallback onOpenUser;
  final VoidCallback onOpenListing;
  final VoidCallback onOpenAppeal;

  @override
  Widget build(BuildContext context) {
    final user = _userValue(item);
    final listing = _listingValue(item);
    final isAppeal = _value(item, const ['ticket_id']).isNotEmpty;
    final block = _blockValue(item);
    final status = _value(block, const ['status']);
    final active = status == 'active';
    final permanent = block['permanent'] == true;
    final phone = _value(user, const ['phone']);
    final name = _value(user, const ['display_name', 'name', 'phone']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RemoteAvatar(
                  imageUrl: _avatarUrl(
                      _value(user, const ['avatar_url', 'photo_url'])),
                  fallbackText: name.isEmpty ? 'Пользователь' : name,
                  radius: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Пользователь' : name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(formatRussianPhone(phone)),
                    ],
                  ),
                ),
                Chip(label: Text(_statusLabel(status))),
              ],
            ),
            const SizedBox(height: 10),
            _Line('Причина', _value(block, const ['reason'])),
            _Line('Начало', _formatDate(_value(block, const ['starts_at']))),
            _Line(
              'Срок',
              permanent
                  ? 'Бессрочно'
                  : _formatDate(_value(block, const ['ends_at'])),
            ),
            _Line('Permanent', permanent ? 'да' : 'нет'),
            if (_value(listing, const ['title']).isNotEmpty)
              _Line('Объявление', _value(listing, const ['title'])),
            _Line(
              'Прошлых блокировок',
              _value(
                  block, const ['previous_blocks_count', 'violations_count']),
            ),
            if (isAppeal)
              _Line('Статус апелляции', _value(item, const ['status'])),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (active)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onUnblock,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Разблокировать'),
                  ),
                if (active)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onExtend,
                    icon: const Icon(Icons.event),
                    label: const Text('Изменить срок'),
                  ),
                if (active && !permanent)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onPermanent,
                    icon: const Icon(Icons.all_inclusive),
                    label: const Text('Сделать бессрочной'),
                  ),
                OutlinedButton.icon(
                  onPressed: onOpenUser,
                  icon: const Icon(Icons.person),
                  label: const Text('Пользователь'),
                ),
                if (_value(listing, const ['id']).isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: onOpenListing,
                    icon: const Icon(Icons.article),
                    label: const Text('Объявление'),
                  ),
                if (isAppeal)
                  OutlinedButton.icon(
                    onPressed: onOpenAppeal,
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Апелляция'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTextDialog extends StatefulWidget {
  const _AdminTextDialog({
    required this.title,
    required this.label,
  });

  final String title;
  final String label;

  @override
  State<_AdminTextDialog> createState() => _AdminTextDialogState();
}

class _AdminTextDialogState extends State<_AdminTextDialog> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value'),
    );
  }
}

class _AdminBlocksState extends StatelessWidget {
  const _AdminBlocksState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockFilter {
  const _BlockFilter(this.status, this.label);
  final String status;
  final String label;
}

Map<String, dynamic> _mapValue(dynamic value) {
  return value is Map
      ? value.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
}

Map<String, dynamic> _blockValue(Map<String, dynamic> item) {
  final nested = _mapValue(item['block']);
  return nested.isEmpty ? item : nested;
}

Map<String, dynamic> _userValue(Map<String, dynamic> item) {
  final user = _mapValue(item['user']);
  if (user.isNotEmpty) return user;
  return _mapValue(_blockValue(item)['user']);
}

Map<String, dynamic> _listingValue(Map<String, dynamic> item) {
  final listing = _mapValue(item['listing']);
  if (listing.isNotEmpty) return listing;
  return _mapValue(_blockValue(item)['listing']);
}

String _avatarUrl(String rawUrl) {
  if (rawUrl.trim().isEmpty) return '';
  return resolvePublicMediaUrl(rawUrl, categoryHint: 'avatars');
}

String _value(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

String _formatDate(String raw) {
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.'
      '${local.year}';
}

String _statusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Активна';
    case 'lifted':
      return 'Снята';
    case 'expired':
      return 'Истекла';
    default:
      return status.isEmpty ? 'Статус' : status;
  }
}
