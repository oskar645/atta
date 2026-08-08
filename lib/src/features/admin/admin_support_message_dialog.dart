import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

Future<Map<String, dynamic>?> showAdminSupportMessageDialog({
  required BuildContext context,
  required String userId,
  required String userName,
  required String userHandle,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _AdminSupportMessageDialog(
      userId: userId,
      userName: userName,
      userHandle: userHandle,
    ),
  );
}

class _AdminSupportMessageDialog extends StatefulWidget {
  const _AdminSupportMessageDialog({
    required this.userId,
    required this.userName,
    required this.userHandle,
  });

  final String userId;
  final String userName;
  final String userHandle;

  @override
  State<_AdminSupportMessageDialog> createState() =>
      _AdminSupportMessageDialogState();
}

class _AdminSupportMessageDialogState
    extends State<_AdminSupportMessageDialog> {
  static const Uuid _uuid = Uuid();

  late final String _idempotencyKey;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _idempotencyKey = _uuid.v4();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Введите сообщение');
      return;
    }

    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final result =
          await context.read<AdminService>().sendSupportMessageToUser(
                userId: widget.userId,
                message: message,
                idempotencyKey: _idempotencyKey,
              );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _errorText(error);
      });
    }
  }

  String _errorText(Object error) {
    if (error is ApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    return 'Не удалось отправить сообщение. Попробуйте ещё раз.';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.userName.trim().isEmpty
        ? 'Пользователь'
        : widget.userName.trim();
    final handle = widget.userHandle.trim();

    return AlertDialog(
      title: const Text('Написать'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (handle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                handle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Сообщение',
                errorText: _error.isEmpty ? null : _error,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Отправить'),
        ),
      ],
    );
  }
}
