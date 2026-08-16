import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/utils/media_url.dart';

const double feedAdBannerAspectRatio = 2.9;

typedef FeedAdImageReadyResolver = Future<void> Function(
  BuildContext context,
  String imageUrl,
);

typedef FeedAdDebugImageBuilder = Widget Function(
  BuildContext context,
  String imageUrl,
);

class FeedAdBanner extends StatefulWidget {
  final FeedAd ad;
  final VoidCallback? onTap;
  final ValueChanged<FeedAd>? onTapAd;
  final ValueChanged<FeedAd>? onDisplayedAdChanged;
  final bool showBadge;

  const FeedAdBanner({
    super.key,
    required this.ad,
    this.onTap,
    this.onTapAd,
    this.onDisplayedAdChanged,
    this.showBadge = true,
  });

  @visibleForTesting
  static FeedAdImageReadyResolver? debugImageReadyResolver;

  @visibleForTesting
  static FeedAdDebugImageBuilder? debugImageBuilder;

  @override
  State<FeedAdBanner> createState() => _FeedAdBannerState();
}

class _FeedAdBannerState extends State<FeedAdBanner> {
  FeedAd? _displayedAd;
  Object? _imageLoadToken;

  @override
  void initState() {
    super.initState();
    _displayedAd = widget.ad;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onDisplayedAdChanged?.call(widget.ad);
    });
  }

  @override
  void didUpdateWidget(covariant FeedAdBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final displayed = _displayedAd;
    if (displayed == null) {
      _setDisplayedAd(widget.ad);
      return;
    }

    if (displayed.id == widget.ad.id &&
        displayed.imageUrl == widget.ad.imageUrl) {
      if (displayed != widget.ad) {
        _setDisplayedAd(widget.ad);
      }
      return;
    }

    _prepareAndShow(widget.ad);
  }

  Future<void> _prepareAndShow(FeedAd ad) async {
    final imageUrl = resolvePublicMediaUrl(
      ad.imageUrl,
      categoryHint: 'feed-ads',
    );
    final token = Object();
    _imageLoadToken = token;

    try {
      final resolver = FeedAdBanner.debugImageReadyResolver;
      if (resolver != null) {
        await resolver(context, imageUrl);
      } else {
        await precacheImage(CachedNetworkImageProvider(imageUrl), context);
      }
    } catch (_) {
      return;
    }

    if (!mounted || !identical(_imageLoadToken, token)) return;
    _setDisplayedAd(ad);
  }

  void _setDisplayedAd(FeedAd ad) {
    setState(() {
      _displayedAd = ad;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onDisplayedAdChanged?.call(ad);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = _displayedAd ?? widget.ad;
    final borderRadius = BorderRadius.circular(16);
    final imageUrl = resolvePublicMediaUrl(
      ad.imageUrl,
      categoryHint: 'feed-ads',
    );
    final debugImageBuilder = FeedAdBanner.debugImageBuilder;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          onTap: widget.onTapAd != null && ad.hasLink
              ? () => widget.onTapAd!(ad)
              : widget.onTap,
          child: AspectRatio(
            aspectRatio: feedAdBannerAspectRatio,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              child: Stack(
                key: ValueKey('${ad.id}:${ad.imageUrl}'),
                fit: StackFit.expand,
                children: [
                  if (debugImageBuilder != null)
                    debugImageBuilder(context, imageUrl)
                  else
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 180),
                      fadeOutDuration: const Duration(milliseconds: 120),
                      placeholder: (_, __) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          size: 36,
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.54),
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                  if (widget.showBadge)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Реклама',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          ad.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
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
