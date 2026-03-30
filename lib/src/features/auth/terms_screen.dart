import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const String _termsText = '''
ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ

Дата последнего обновления: 2026

Настоящее Пользовательское соглашение регулирует использование приложения ATTA.

1. Пользователь принимает условия при использовании приложения.
2. Пользователь обязан указывать достоверные данные.
3. Запрещено размещать незаконные товары и мошеннические объявления.
4. Администрация может удалять объявления без предупреждения.
5. Приложение не несёт ответственности за сделки между пользователями.
''';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользовательское соглашение'),
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
                  _termsText,
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
