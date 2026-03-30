import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const String _privacyText = '''
ПОЛИТИКА КОНФИДЕНЦИАЛЬНОСТИ

Дата последнего обновления: 2026

Мы собираем следующие данные:
- имя
- email
- сообщения
- данные объявлений

Данные используются для:
- работы приложения
- связи между пользователями

Мы не передаём данные третьим лицам, кроме случаев, предусмотренных законом.

Пользователь может удалить свой аккаунт и данные.
''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Политика конфиденциальности'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  _privacyText,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
