import 'package:flutter/material.dart';

class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    this.title = 'Что-то пошло не так',
    this.message = 'Попробуйте снова.',
    this.onRetry,
    this.compact = false,
  });

  final String title;
  final String message;
  final Future<void> Function()? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: compact ? 40 : 52,
          color: Theme.of(context).colorScheme.error,
        ),
        SizedBox(height: compact ? 10 : 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () async {
              await onRetry?.call();
            },
            child: const Text('Повторить'),
          ),
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: compact
            ? content
            : Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: content,
                ),
              ),
      ),
    );
  }
}
