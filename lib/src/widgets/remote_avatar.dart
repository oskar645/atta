import 'package:atta/src/utils/media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class RemoteAvatar extends StatelessWidget {
  const RemoteAvatar({
    super.key,
    required this.imageUrl,
    required this.fallbackText,
    this.radius = 20,
    this.backgroundColor,
    this.textStyle,
    this.imageProvider,
    this.isLoading = false,
    this.categoryHint = 'avatars',
  });

  final String imageUrl;
  final String fallbackText;
  final double radius;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final ImageProvider<Object>? imageProvider;
  final bool isLoading;
  final String categoryHint;

  @override
  Widget build(BuildContext context) {
    final resolution = resolveMediaUrl(
      imageUrl,
      categoryHint: categoryHint,
    );
    final trimmedUrl = resolution.resolvedUrl.trim();
    final trimmedFallback = fallbackText.trim();
    final letter =
        trimmedFallback.isEmpty ? 'U' : trimmedFallback[0].toUpperCase();
    final bg = backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget fallback() {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          letter,
          style: textStyle ??
              TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
      );
    }

    final size = radius * 2;
    Widget avatarChild() {
      if (imageProvider != null) {
        return Image(
          image: imageProvider!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => fallback(),
        );
      }
      if (trimmedUrl.isEmpty) {
        return fallback();
      }
      return CachedNetworkImage(
        imageUrl: trimmedUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => SkeletonCircle(size: size),
        errorWidget: (_, __, ___) {
          if (kDebugMode) {
            debugPrint(
              'Media render failed category=$categoryHint provider=${resolution.provider} original=${resolution.originalUrl} resolved=${resolution.resolvedUrl}',
            );
          }
          return fallback();
        },
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipOval(child: avatarChild()),
          if (isLoading)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    key: Key('remote_avatar_loading'),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
