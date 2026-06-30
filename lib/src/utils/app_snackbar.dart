import 'package:flutter/material.dart';

final Map<String, DateTime> _snackLastShownAt = <String, DateTime>{};

void showAppSnack(
  BuildContext context,
  String message, {
  bool isError = false,
  Duration minRepeatGap = const Duration(milliseconds: 2500),
}) {
  final text = message.trim();
  if (text.isEmpty) return;

  final key = text;
  final now = DateTime.now();
  final last = _snackLastShownAt[key];
  if (last != null && now.difference(last) < minRepeatGap) return;
  _snackLastShownAt[key] = now;

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Colors.red.shade700 : null,
    ),
  );
}
