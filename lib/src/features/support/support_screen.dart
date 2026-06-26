import 'dart:io';

import 'package:atta/src/features/listings/photo_viewer_screen.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/app_error_view.dart';
import 'package:atta/src/widgets/media_preview_box.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
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

  final _text = TextEditingController();
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final List<Map<String, dynamic>> _draftMessages = <Map<String, dynamic>>[];
  String? _ticketId;
  XFile? _selectedImage;
  bool _sending = false;
  bool _loadingTicket = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadMyTicket();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadMyTicket() async {
    final auth = context.read<AuthService>();
    final support = context.read<SupportService>();
    final uid = auth.currentUser!.uid;

    try {
      final existing = await support.getOrCreateMyTicketId(uid: uid);
      if (!mounted) return;
      setState(() {
        _ticketId = existing;
        _loadingTicket = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTicket = false;
        _loadError = _supportErrorText(error);
      });
    }
  }

  Future<String> _getMyName() async {
    final auth = context.read<AuthService>();
    final profile = context.read<ProfileService>();
    final u = auth.currentUser!;

    final data = await profile.getProfile(u.uid);
    final dn = (data['displayName'] ?? data['name'] ?? '').toString().trim();
    if (dn.isNotEmpty) return dn;

    final ad = (u.displayName ?? '').trim();
    if (ad.isNotEmpty) return ad;
    return u.email ?? 'Пользователь';
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final image = _selectedImage;
    if (text.isEmpty && image == null) {
      showAppSnack(
        context,
        'Нельзя отправить пустое сообщение.',
        isError: true,
      );
      return;
    }

    final support = context.read<SupportService>();
    final auth = context.read<AuthService>();
    final localId = 'local-${_uuid.v4()}';

    setState(() {
      _sending = true;
      _text.clear();
    });

    try {
      if (_ticketId == null) {
        final draft = <String, dynamic>{
          'id': localId,
          'ticket_id': 'draft',
          'sender': 'user',
          'text': text,
          'image_url': image == null ? '' : 'file://${image.path}',
          'local_image_path': image?.path,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'local_status': 'pending',
        };
        if (mounted) {
          setState(() {
            _draftMessages.insert(0, draft);
            _selectedImage = null;
          });
        }

        final name = await _getMyName();
        final createdTicketId = await support.createTicketAndSendFirstMessage(
          uid: auth.currentUser!.uid,
          name: name,
          text: text,
          imageFile: image == null ? null : File(image.path),
        );
        if (!mounted) return;
        setState(() {
          _ticketId = createdTicketId;
          _draftMessages.clear();
        });
        return;
      }

      if (mounted) {
        setState(() {
          _selectedImage = null;
        });
      }
      await support.sendMessage(
        ticketId: _ticketId!,
        text: text,
        imageFile: image == null ? null : File(image.path),
      );
    } catch (error) {
      if (!mounted) return;
      if (_ticketId == null) {
        setState(() {
          for (var i = 0; i < _draftMessages.length; i += 1) {
            if ((_draftMessages[i]['id'] ?? '').toString() != localId) continue;
            _draftMessages[i] = <String, dynamic>{
              ..._draftMessages[i],
              'local_status': 'failed',
              'error_text': _supportErrorText(error),
            };
            break;
          }
        });
      } else {
        showAppSnack(context, _supportErrorText(error), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _retryDraftMessage(Map<String, dynamic> message) async {
    final text = (message['text'] ?? '').toString();
    final localImagePath =
        (message['local_image_path'] ?? '').toString().trim();
    final support = context.read<SupportService>();
    final auth = context.read<AuthService>();

    setState(() {
      for (var i = 0; i < _draftMessages.length; i += 1) {
        if ((_draftMessages[i]['id'] ?? '').toString() !=
            (message['id'] ?? '').toString()) {
          continue;
        }
        _draftMessages[i] = <String, dynamic>{
          ..._draftMessages[i],
          'local_status': 'pending',
          'error_text': null,
        };
      }
    });

    try {
      final name = await _getMyName();
      final createdTicketId = await support.createTicketAndSendFirstMessage(
        uid: auth.currentUser!.uid,
        name: name,
        text: text,
        imageFile: localImagePath.isEmpty ? null : File(localImagePath),
      );
      if (!mounted) return;
      setState(() {
        _ticketId = createdTicketId;
        _draftMessages.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _draftMessages.length; i += 1) {
          if ((_draftMessages[i]['id'] ?? '').toString() !=
              (message['id'] ?? '').toString()) {
            continue;
          }
          _draftMessages[i] = <String, dynamic>{
            ..._draftMessages[i],
            'local_status': 'failed',
            'error_text': _supportErrorText(error),
          };
        }
      });
    }
  }

  String _supportErrorText(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 413 || error.code == 'payload_too_large') {
        return 'Файл слишком большой. Выберите другое фото.';
      }
      if (error.isTimeout || error.isNetworkError) {
        return kNetworkVpnHintMessage;
      }
      if (error.message.trim().isNotEmpty) {
        return error.message.trim();
      }
    }
    if (shouldShowNetworkVpnHint(error)) {
      return kNetworkVpnHintMessage;
    }
    final text = error.toString().trim();
    if (text.contains('403') || text.contains('Forbidden')) {
      return 'Доступ запрещён.';
    }
    return 'Не удалось выполнить действие. Попробуйте снова.';
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

  Future<void> _pickImage(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1800,
      maxHeight: 1800,
    );
    if (image == null || !mounted) return;
    setState(() => _selectedImage = image);
  }

  void _openAttachMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openImageFullScreen(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    final viewerUrl =
        url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(photoUrls: [viewerUrl]),
      ),
    );
  }

  Widget _buildSelectedPreview() {
    final image = _selectedImage;
    if (image == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.file(
                File(image.path),
                width: 104,
                height: 104,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _selectedImage = null),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const Center(
        child: Text('Пока нет сообщений. Напишите нам, и мы поможем.'),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final m = items[i];
        final createdAt = _parseCreatedAt(m['created_at']);
        final nextCreatedAt = i + 1 < items.length
            ? _parseCreatedAt(items[i + 1]['created_at'])
            : null;
        final showDateDivider =
            nextCreatedAt == null || !_isSameDay(createdAt, nextCreatedAt);

        return Column(
          key: ValueKey((m['id'] ?? 'support-$i').toString()),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateDivider)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatCenterDate(createdAt),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                ),
              ),
            _SupportMessageBubble(
              message: m,
              timeText: _formatTime(createdAt),
              onOpenImage: _openImageFullScreen,
              onRetry: (m['local_status'] ?? '').toString() == 'failed'
                  ? () async {
                      if (_ticketId == null) {
                        await _retryDraftMessage(m);
                        return;
                      }
                      try {
                        await context.read<SupportService>().retryMessage(
                              ticketId: _ticketId!,
                              messageId: (m['id'] ?? '').toString(),
                            );
                      } catch (error) {
                        if (!context.mounted) return;
                        showAppSnack(
                          context,
                          _supportErrorText(error),
                          isError: true,
                        );
                      }
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final support = context.read<SupportService>();
    Widget messagesBody;

    if (_loadingTicket) {
      messagesBody = ListView(
        reverse: true,
        padding: const EdgeInsets.all(12),
        children: const [
          SkeletonMessageBubble(isMine: true),
          SkeletonMessageBubble(),
          SkeletonMessageBubble(isMine: true),
        ],
      );
    } else if (_loadError != null) {
      messagesBody = AppErrorView(
        message: _loadError!,
        onRetry: _loadMyTicket,
      );
    } else if (_ticketId == null) {
      messagesBody = _buildMessageList(_draftMessages);
    } else {
      final cachedItems = support.peekMessages(_ticketId!);
      messagesBody = StreamBuilder<List<Map<String, dynamic>>>(
        stream: support.streamMessages(_ticketId!),
        initialData: cachedItems.isEmpty ? null : cachedItems,
        builder: (context, snap) {
          if (snap.hasError && (snap.data == null || snap.data!.isEmpty)) {
            return AppErrorView(
              message: _supportErrorText(snap.error!),
              onRetry: () => support.refreshMessages(_ticketId!),
            );
          }
          if (!snap.hasData) {
            return ListView(
              reverse: true,
              padding: const EdgeInsets.all(12),
              children: const [
                SkeletonMessageBubble(isMine: true),
                SkeletonMessageBubble(),
                SkeletonMessageBubble(),
              ],
            );
          }
          return _buildMessageList(snap.data!);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Поддержка ATTA'),
            SizedBox(height: 2),
            Text(
              'Обычно отвечаем быстро',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(child: messagesBody),
          _buildSelectedPreview(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Добавить фото',
                    onPressed: _sending ? null : _openAttachMenu,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Напишите в поддержку...',
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _sending ? null : _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
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

class _SupportMessageBubble extends StatelessWidget {
  const _SupportMessageBubble({
    required this.message,
    required this.timeText,
    required this.onOpenImage,
    this.onRetry,
  });

  final Map<String, dynamic> message;
  final String timeText;
  final ValueChanged<String> onOpenImage;
  final VoidCallback? onRetry;

  bool get _isMine => (message['sender'] ?? '').toString() == 'user';
  bool get _failed => (message['local_status'] ?? '').toString() == 'failed';
  bool get _pending => (message['local_status'] ?? '').toString() == 'pending';

  @override
  Widget build(BuildContext context) {
    final text = _messageText(message);
    final imageUrl = (message['image_url'] ?? '').toString().trim();
    final hasImage = imageUrl.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final bubbleColor =
        _isMine ? const Color(0xFFD9E7FF) : scheme.surfaceContainerHighest;
    final textColor = _isMine ? const Color(0xFF17212F) : scheme.onSurface;
    final secondaryTextColor =
        _isMine ? const Color(0xFF4F5B6B) : scheme.onSurfaceVariant;

    return Align(
      alignment: _isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: EdgeInsets.all(hasImage ? 6 : 12),
        constraints: const BoxConstraints(maxWidth: 292),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    _SupportMessageImage(
                      imageUrl: imageUrl,
                      onOpen: () => onOpenImage(imageUrl),
                    ),
                    if (_pending)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (text.isNotEmpty) ...[
              if (hasImage) const SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hasImage ? 6 : 0),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_failed) ...[
                  Text(
                    'Не отправлено',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const SizedBox(width: 8),
                ] else if (_pending) ...[
                  Text(
                    'Отправка...',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: secondaryTextColor,
                        ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  timeText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: secondaryTextColor,
                      ),
                ),
              ],
            ),
            if (_failed && onRetry != null) ...[
              if ((message['error_text'] ?? '').toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    (message['error_text'] ?? '').toString().trim(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              const SizedBox(height: 2),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _messageText(Map<String, dynamic> message) {
  final candidates = <dynamic>[
    message['text'],
    message['body'],
    message['message'],
    message['content'],
    message['caption'],
  ];
  for (final candidate in candidates) {
    final value = candidate?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

class _SupportMessageImage extends StatelessWidget {
  const _SupportMessageImage({
    required this.imageUrl,
    required this.onOpen,
  });

  final String imageUrl;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    const maxWidth = 248.0;
    const maxHeight = 280.0;

    Widget fallback([String message = 'Фото недоступно']) {
      return Container(
        width: maxWidth,
        height: 180,
        color: Colors.black12,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      );
    }

    final localPath = imageUrl.startsWith('file://')
        ? imageUrl.replaceFirst('file://', '')
        : null;
    if (localPath != null && localPath.isNotEmpty) {
      return GestureDetector(
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.file(
              File(localPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
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
}
