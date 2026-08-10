import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AdminCopyUserIdButton extends StatelessWidget {
  const AdminCopyUserIdButton({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context) {
    final targetUserId = userId.trim();
    if (targetUserId.isEmpty) return const SizedBox.shrink();

    final currentUser = context.watch<AuthService>().currentUser;
    final currentUserId = currentUser?.uid.trim() ?? '';
    if (currentUser == null || currentUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    if (currentUser.isAdmin) {
      return _CopyUserIdButton(userId: targetUserId);
    }

    return StreamBuilder<bool>(
      stream: context.read<AdminService>().streamIsAdmin(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return _CopyUserIdButton(userId: targetUserId);
      },
    );
  }
}

class _CopyUserIdButton extends StatelessWidget {
  const _CopyUserIdButton({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('admin_copy_user_id_button'),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: userId));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID скопирован')),
        );
      },
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.copy_outlined, size: 14),
      label: const Text(
        'ID',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}
