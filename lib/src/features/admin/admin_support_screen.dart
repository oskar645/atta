import 'package:flutter/material.dart';
import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:provider/provider.dart';
import 'package:atta/src/features/profile/seller_public_profile_screen.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/media_preview_box.dart';

String _ticketUserId(Map<String, dynamic> ticket) {
  const candidates = <String>[
    'uid',
    'user_id',
    'userId',
    'requesterId',
    'requester_id',
    'customerId',
    'customer_id',
    'createdById',
    'created_by_id',
    'authorId',
    'author_id',
  ];
  for (final key in candidates) {
    final value = (ticket[key] ?? '').toString().trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

class AdminSupportTab extends StatelessWidget {
  const AdminSupportTab({super.key});

  void _openUserProfile(BuildContext context, String uid) {
    if (uid.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerPublicProfileScreen(sellerId: uid),
      ),
    );
  }

  Future<void> _hideTicket(
    BuildContext context, {
    required Map<String, dynamic> ticket,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить переписку из списка поддержки?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final ticketId = (ticket['id'] ?? '').toString().trim();
    final updatedAt = (ticket['updated_at'] ?? '').toString().trim();
    if (ticketId.isEmpty || updatedAt.isEmpty) {
      showAppSnack(
        context,
        'Не удалось скрыть переписку. Попробуйте ещё раз.',
        isError: true,
      );
      return;
    }

    try {
      await context.read<SupportService>().hideAdminTicket(
            ticketId: ticketId,
            updatedAt: updatedAt,
          );
      if (!context.mounted) return;
      showAppSnack(context, 'Переписка скрыта');
    } catch (_) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'Не удалось скрыть переписку. Попробуйте ещё раз.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = context.read<SupportService>();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: support.streamTicketsForAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Ошибка: ${snap.error}'));
        }

        final docs = snap.data ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Пока нет обращений'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final data = docs[i];

            final uid = _ticketUserId(data);
            final name = (data['name'] ?? 'Пользователь').toString();
            final last = (data['last_message'] ?? '').toString();
            final unreadForAdmin = data['unread_for_admin'] == true;

            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: Icon(
                Icons.support_agent,
                color: unreadForAdmin
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                last.isEmpty ? 'Нет сообщений' : last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Профиль пользователя',
                    icon: const Icon(Icons.person_outline),
                    onPressed: () => _openUserProfile(context, uid),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminTicketScreen(
                      ticketId: data['id'].toString(),
                      titleName: name,
                      userUid: uid,
                    ),
                  ),
                );
              },
              onLongPress: () => _hideTicket(context, ticket: data),
            );
          },
        );
      },
    );
  }
}

class AdminTicketScreen extends StatefulWidget {
  final String ticketId;
  final String titleName;
  final String userUid;

  const AdminTicketScreen({
    super.key,
    required this.ticketId,
    required this.titleName,
    required this.userUid,
  });

  @override
  State<AdminTicketScreen> createState() => _AdminTicketScreenState();
}

class _AdminTicketScreenState extends State<AdminTicketScreen> {
  final TextEditingController _text = TextEditingController();
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  bool _sending = false;
  bool _openingProfile = false;
  static const List<String> _ruMonthsGenitive = <String>[
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  Future<void> _openUserProfile() async {
    if (_openingProfile) return;

    final userUid = widget.userUid.trim();
    if (userUid.isEmpty) {
      showAppSnack(
        context,
        'Не удалось открыть профиль пользователя',
        isError: true,
      );
      return;
    }

    _openingProfile = true;
    if (mounted) {
      setState(() {});
    }
    try {
      final row = await context.read<ProfileService>().getProfile(userUid);
      if (!mounted) return;
      if (row.isEmpty) {
        showAppSnack(
          context,
          'Профиль пользователя недоступен',
          isError: true,
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SellerPublicProfileScreen(
            sellerId: userUid,
            showAdminFields: true,
            titleText: 'Профиль пользователя',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Не удалось открыть профиль пользователя',
        isError: true,
      );
    } finally {
      _openingProfile = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 4 быстрых кнопки: короткие названия + длинный текст (вставляем в поле)
  final List<Map<String, String>> _quickReplies = const [
    {
      'label': 'Приветствие',
      'text': 'Здравствуйте! 👋 Спасибо за обращение в поддержку. Мы получили ваше сообщение и уже начали разбираться. '
          'Пожалуйста, подождите немного — мы ответим вам здесь, как только появится информация.',
    },
    {
      'label': 'На проверке',
      'text': 'Мы передали ваш вопрос на проверку и уточнение. ✅ '
          'Обычно это занимает немного времени. Если понадобятся детали — мы обязательно напишем вам в этом чате.',
    },
    {
      'label': 'Нужны детали',
      'text': 'Чтобы быстрее помочь, уточните, пожалуйста:\n'
          '1) что именно не работает/что произошло,\n'
          '2) на каком устройстве (Android/iPhone),\n'
          '3) можно ли скриншот.\n'
          'После этого мы сразу продолжим проверку.',
    },
    {
      'label': 'Решено',
      'text':
          'Готово ✅ Мы исправили/проверили ситуацию. Пожалуйста, попробуйте ещё раз. '
              'Если проблема повторится — напишите нам сюда, мы сразу продолжим.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _messagesStream = context.read<SupportService>().streamAdminMessages(
          widget.ticketId,
        );

    // Помечаем как прочитанный админом при открытии
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final support = context.read<SupportService>();
      try {
        await support.markReadByAdmin(widget.ticketId);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    final support = context.read<SupportService>();

    setState(() => _sending = true);
    try {
      await support.adminReply(
        ticketId: widget.ticketId,
        text: t,
      );
      _text.clear();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, 'Ошибка отправки: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _applyQuickReply(String value) {
    _text.text = value;
    _text.selection = TextSelection.fromPosition(
      TextPosition(offset: _text.text.length),
    );
    setState(() {});
  }

  DateTime _parseCreatedAt(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    final parsed = DateTime.tryParse((raw ?? '').toString());
    return (parsed ?? DateTime.now()).toLocal();
  }

  String _formatTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _formatCenterDate(DateTime dt) {
    final month = _ruMonthsGenitive[dt.month - 1];
    return '${dt.day} $month ${dt.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _openImage(String imageUrl) {
    final url = imageUrl.trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photoUrls: [url]),
      ),
    );
  }

  Widget _messageImage(String imageUrl) {
    return GestureDetector(
      onTap: () => _openImage(imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1,
          child: MediaPreviewBox(
            imageUrl: imageUrl,
            categoryHint: 'support',
            borderRadius: 0,
            errorLabel: 'Фото недоступно',
            placeholderLabel: 'Загрузка фото...',
          ),
        ),
      ),
    );
  }

  Widget _buildQuickReplies() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _quickReplies.map((q) {
          final label = q['label'] ?? 'Ответ';
          final text = q['text'] ?? '';

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton(
              onPressed: _sending ? null : () => _applyQuickReply(text),
              child: Text(label),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _openUserProfile,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.titleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: _openingProfile
                    ? Theme.of(context).colorScheme.outline
                    : null,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _messagesStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Ошибка: ${snap.error}'));
                }

                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const Center(child: Text('Нет сообщений'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final sender = (m['sender'] ?? '').toString();
                    final text = (m['text'] ?? '').toString();
                    final imageUrl = (m['image_url'] ?? '').toString().trim();
                    final isAdmin = sender == 'admin';
                    final createdAt = _parseCreatedAt(m['created_at']);
                    final nextCreatedAt = i + 1 < items.length
                        ? _parseCreatedAt(items[i + 1]['created_at'])
                        : null;
                    final showDateDivider = nextCreatedAt == null ||
                        !_isSameDay(createdAt, nextCreatedAt);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDateDivider)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Center(
                              child: Text(
                                _formatCenterDate(createdAt),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: isAdmin
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: EdgeInsets.all(imageUrl.isEmpty ? 10 : 6),
                            constraints: const BoxConstraints(maxWidth: 320),
                            decoration: BoxDecoration(
                              color: isAdmin
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (imageUrl.isNotEmpty)
                                  _messageImage(imageUrl),
                                if (text.trim().isNotEmpty) ...[
                                  if (imageUrl.isNotEmpty)
                                    const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: imageUrl.isEmpty ? 0 : 6,
                                      ),
                                      child: Text(text),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(createdAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ===== БЫСТРЫЕ ОТВЕТЫ =====
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: _buildQuickReplies(),
            ),
          ),

          // ===== ПОЛЕ ВВОДА + ОТПРАВКА =====
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(
                        hintText: 'Ответ...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _sending ? null : _send(_text.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : () => _send(_text.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
