import 'package:atta/src/utils/media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MediaPreviewBox extends StatelessWidget {
  const MediaPreviewBox({
    super.key,
    required this.imageUrl,
    this.categoryHint,
    this.borderRadius = 12,
    this.aspectRatio,
    this.width,
    this.height,
    this.emptyLabel = 'Нет фото',
    this.errorLabel = 'Фото недоступно',
    this.placeholderLabel,
    this.icon = Icons.image_outlined,
    this.errorIcon = Icons.broken_image_outlined,
  });

  final String imageUrl;
  final String? categoryHint;
  final double borderRadius;
  final double? aspectRatio;
  final double? width;
  final double? height;
  final String emptyLabel;
  final String errorLabel;
  final String? placeholderLabel;
  final IconData icon;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) {
    Widget content = _buildContent(context);
    if (aspectRatio != null) {
      content = AspectRatio(
        aspectRatio: aspectRatio!,
        child: content,
      );
    }
    if (width != null || height != null) {
      content = SizedBox(
        width: width,
        height: height,
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: content,
    );
  }

  Widget _buildContent(BuildContext context) {
    final resolution = resolveMediaUrl(
      imageUrl,
      categoryHint: categoryHint,
    );
    final resolvedUrl = resolution.resolvedUrl.trim();
    if (resolvedUrl.isEmpty) {
      return _fallback(context, emptyLabel, icon);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: CachedNetworkImage(
        imageUrl: resolvedUrl,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        placeholder: (_, __) =>
            _fallback(context, placeholderLabel ?? 'Загрузка фото...', icon),
        errorWidget: (_, __, ___) {
          if (kDebugMode) {
            debugPrint(
              'Media render failed category=${resolution.category} provider=${resolution.provider} original=${resolution.originalUrl} resolved=${resolution.resolvedUrl}',
            );
          }
          return _fallback(context, errorLabel, errorIcon);
        },
      ),
    );
  }

  Widget _fallback(BuildContext context, String label, IconData iconData) {
    final outline = Theme.of(context).colorScheme.outline;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, size: 28, color: outline),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: outline,
            ),
          ),
        ],
      ),
    );
  }
}
