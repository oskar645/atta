import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/reviews_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/utils/app_snackbar.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

String reviewAuthorAvatarUrl(Map<String, dynamic> review) {
  final preview = review['author_preview'];
  if (preview is Map) {
    final avatar =
        (preview['avatar_url'] ?? preview['photo_url'] ?? '').toString().trim();
    if (avatar.isNotEmpty) return avatar;
  }
  return (review['reviewer_avatar_url'] ?? review['avatar_url'] ?? '')
      .toString()
      .trim();
}

class SellerReviewsScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String listingId;

  const SellerReviewsScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.listingId,
  });

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = context.read<AuthService>().currentUser;
      if (me == null) return;

      if (me.uid == widget.sellerId) {
        try {
          await context
              .read<ReviewsService>()
              .resetNewReviewsCount(widget.sellerId);
        } catch (_) {}
      }
    });
  }

  Future<void> _openAddReview() async {
    final me = context.read<AuthService>().currentUser;
    if (me == null) return;

    if (me.uid == widget.sellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нельзя оставить отзыв самому себе')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddReviewSheet(
        sellerId: widget.sellerId,
        listingId: widget.listingId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reviews = context.read<ReviewsService>();
    final admin = context.read<AdminService>();
    final me = context.read<AuthService>().currentUser;
    final canCheckAdmin = me != null && me.uid.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text('Отзывы: ${widget.sellerName}')),
      body: StreamBuilder<bool>(
        stream: canCheckAdmin
            ? admin.streamIsAdmin(me.uid)
            : Stream<bool>.value(false),
        initialData: false,
        builder: (context, adminSnap) {
          final isAdmin = adminSnap.data == true;

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: reviews.streamSellerReviews(widget.sellerId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Ошибка отзывов:\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snap.data ?? const <Map<String, dynamic>>[];

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  FilledButton.icon(
                    onPressed: _openAddReview,
                    icon: Icon(
                      Icons.rate_review_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: const Text('Оставить отзыв'),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text(
                          'Пока нет отзывов.\nБудь первым 🙂',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    ),
                  ...items.map(
                    (r) => _ReviewTile(
                      sellerId: widget.sellerId,
                      review: r,
                      isAdmin: isAdmin,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final String sellerId;
  final Map<String, dynamic> review;
  final bool isAdmin;

  const _ReviewTile({
    required this.sellerId,
    required this.review,
    required this.isAdmin,
  });

  String _dateText(dynamic v) {
    DateTime? dt;
    if (v is DateTime) dt = v;
    if (v is String) dt = DateTime.tryParse(v);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _shortUid(String v) {
    final s = v.trim();
    if (s.length <= 10) return s;
    return '${s.substring(0, 6)}…${s.substring(s.length - 4)}';
  }

  Future<void> _deleteReview(BuildContext context) async {
    final reviewId = (review['id'] ?? '').toString().trim();
    if (reviewId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить отзыв?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<ReviewsService>().deleteReview(reviewId: reviewId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отзыв удалён')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser;
    final isSeller = me != null && me.uid == sellerId;

    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final text = (review['comment'] ?? '').toString().trim();

    final reviewerNameRaw = (review['reviewer_name'] ?? '').toString().trim();
    final reviewerId = (review['reviewer_id'] ?? '').toString().trim();

    final reviewerName = reviewerNameRaw.isNotEmpty
        ? reviewerNameRaw
        : (reviewerId.isNotEmpty ? _shortUid(reviewerId) : 'Пользователь');
    final reviewerAvatar = reviewAuthorAvatarUrl(review);

    final createdAt = _dateText(review['created_at']);
    final replyText = (review['reply_text'] ?? '').toString().trim();

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
                  imageUrl: reviewerAvatar,
                  fallbackText: reviewerName,
                  radius: 18,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    reviewerName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  createdAt,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
                if (isAdmin)
                  IconButton(
                    onPressed: () => _deleteReview(context),
                    tooltip: 'Удалить отзыв',
                    iconSize: 18,
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              children: List.generate(5, (i) {
                final filled = i < rating;
                return Icon(
                  filled ? Icons.star : Icons.star_border,
                  size: 16,
                  color: filled
                      ? Colors.amber
                      : Theme.of(context).colorScheme.outline,
                );
              }),
            ),

            const SizedBox(height: 8),
            Text(text.isEmpty ? '—' : text),

            // ✅ Ответ продавца (если есть)
            if (replyText.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Text('Ответ продавца: $replyText'),
              ),
            ],

            // ✅ Кнопка для продавца: ответить / изменить ответ
            if (isSeller) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  final res = await showDialog<String>(
                    context: context,
                    builder: (_) => _ReplyDialog(initial: replyText),
                  );
                  if (res == null || res.trim().isEmpty) return;

                  try {
                    await context.read<ReviewsService>().replyToReview(
                          sellerId: sellerId,
                          reviewId: (review['id'] ?? '').toString(),
                          replyText: res,
                        );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.reply),
                label: Text(replyText.isEmpty ? 'Ответить' : 'Изменить ответ'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddReviewSheet extends StatefulWidget {
  final String sellerId;
  final String listingId;
  const _AddReviewSheet({required this.sellerId, required this.listingId});

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  int _rating = 5;
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _reviewErrorText(Object error) {
    if (error is ApiException) {
      if (error.code == 'REVIEW_ALREADY_EXISTS') {
        return 'Можно оставить только один отзыв';
      }
      final raw = error.message.toLowerCase();
      if (raw.contains('review already exists')) {
        return 'Вы уже оставили отзыв этому пользователю';
      }
      if (error.message.trim().isNotEmpty) {
        return error.message.trim();
      }
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('review already exists')) {
      return 'Вы уже оставили отзыв этому пользователю';
    }
    return 'Не удалось отправить отзыв. Попробуйте ещё раз.';
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthService>().currentUser;

    // ✅ ВАЖНО: берём имя из AuthService (displayName), если нет — email
    final reviewerName = (me?.displayName?.trim().isNotEmpty ?? false)
        ? me!.displayName!.trim()
        : (me?.email ?? 'Пользователь');

    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ваш отзыв',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) {
              final idx = i + 1;
              final filled = idx <= _rating;
              return IconButton(
                onPressed: () => setState(() => _rating = idx),
                icon: Icon(
                  filled ? Icons.star : Icons.star_border,
                  color: filled
                      ? Colors.amber
                      : Theme.of(context).colorScheme.outline,
                ),
              );
            }),
          ),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Напишите, как прошла сделка…',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_saving) return;
                      final me = context.read<AuthService>().currentUser;
                      if (me == null) return;

                      final text = _ctrl.text.trim();
                      if (text.isEmpty) {
                        showAppSnack(
                          context,
                          'Текст отзыва не должен быть пустым',
                          isError: true,
                        );
                        return;
                      }

                      setState(() => _saving = true);
                      try {
                        await context.read<ReviewsService>().addReview(
                              sellerId: widget.sellerId,
                              reviewerId: me.uid,
                              reviewerName: reviewerName,
                              listingId: widget.listingId,
                              rating: _rating,
                              text: text,
                            );

                        if (!context.mounted) return;
                        Navigator.pop(context);
                        showAppSnack(
                          context,
                          'Отзыв отправлен успешно',
                        );
                      } catch (e) {
                        if (!mounted) return;
                        showAppSnack(
                          context,
                          _reviewErrorText(e),
                          isError: true,
                        );
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? 'Отправляем…' : 'Отправить'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyDialog extends StatefulWidget {
  final String initial;
  const _ReplyDialog({required this.initial});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

class _ReplyDialogState extends State<_ReplyDialog> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ответ продавца'),
      content: TextField(
        controller: _c,
        maxLines: 3,
        decoration:
            const InputDecoration(hintText: 'Например: Спасибо за отзыв!'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _c.text),
            child: const Text('Сохранить')),
      ],
    );
  }
}
