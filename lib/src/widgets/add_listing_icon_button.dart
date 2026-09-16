import 'dart:async';

import 'package:atta/src/features/auth/guest_auth_prompt.dart';
import 'package:atta/src/features/listings/add_listing_screen.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddListingIconButton extends StatelessWidget {
  const AddListingIconButton({super.key});

  static const double _tapSize = 52;
  static const double _iconSize = 34;

  static Future<void> openCreateListingFlow(BuildContext context) async {
    final auth = context.read<AuthService>();
    if (!auth.isAuthenticated) {
      final authenticated = await promptGuestAuth(context);
      if (!authenticated || !context.mounted) return;
    }
    if (!context.mounted) return;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AddListingScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Добавить',
      constraints: const BoxConstraints(
        minWidth: _tapSize,
        minHeight: _tapSize,
      ),
      padding: EdgeInsets.zero,
      icon: const Icon(
        Icons.add_circle,
        color: Colors.blue,
        size: _iconSize,
      ),
      onPressed: () async {
        await openCreateListingFlow(context);
      },
    );
  }
}
