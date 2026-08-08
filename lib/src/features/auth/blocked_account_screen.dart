import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/support_service.dart';
import 'package:atta/src/utils/app_snackbar.dart';

class BlockedAccountScreen extends StatefulWidget {
  const BlockedAccountScreen({super.key});

  @override
  State<BlockedAccountScreen> createState() => _BlockedAccountScreenState();
}

class _BlockedAccountScreenState extends State<BlockedAccountScreen> {
  bool _busy = false;

  Future<void> _openAppealDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обратиться в поддержку'),
        content: TextField(
          controller: controller,
          minLines: 4,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'Сообщение',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final support = context.read<SupportService>();
    final auth = context.read<AuthService>();

    setState(() => _busy = true);
    try {
      await support.createBlockAppeal(text: text);
      await auth.syncBlockStatus();
      if (!mounted) return;
      showAppSnack(context, 'Обращение отправлено');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, 'Не удалось отправить обращение: $error',
          isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Не указан';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final block = user?.blockStatus;
    final reason = block?.reason.trim();
    final deadline =
        block?.permanent == true ? 'Бессрочно' : _formatDate(block?.endsAt);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Аккаунт заблокирован'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Ваш аккаунт заблокирован',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 18),
                  _InfoRow(
                    label: 'Причина',
                    value: reason == null || reason.isEmpty
                        ? 'Причина не указана'
                        : reason,
                  ),
                  _InfoRow(label: 'Срок', value: deadline),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _openAppealDialog,
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Обратиться в поддержку'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Выйти'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 3),
          Text(value),
        ],
      ),
    );
  }
}
