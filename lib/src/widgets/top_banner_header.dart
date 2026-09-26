import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/top_banner.dart';
import '../services/top_banners_service.dart';
import '../utils/media_url.dart';

class TopBannerHeaderBackground extends StatefulWidget {
  const TopBannerHeaderBackground(
      {super.key, required this.banner, required this.service});
  final TopBanner? banner;
  final TopBannersService service;

  @visibleForTesting
  static ImageProvider<Object> Function(String imageUrl)? debugImageProvider;

  @override
  State<TopBannerHeaderBackground> createState() => _State();
}

class _State extends State<TopBannerHeaderBackground> {
  bool shown = false;

  @override
  void initState() {
    super.initState();
    _markVisibleAfterFrame();
  }

  @override
  void didUpdateWidget(covariant TopBannerHeaderBackground old) {
    super.didUpdateWidget(old);
    if (old.banner?.id != widget.banner?.id) {
      shown = false;
      _markVisibleAfterFrame();
    }
  }

  void _markVisibleAfterFrame() {
    final banner = widget.banner;
    if (banner == null || shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || shown || widget.banner?.id != banner.id) return;
      shown = true;
      unawaited(widget.service.impression(banner));
    });
  }

  Future<void> open() async {
    final b = widget.banner;
    if (b == null || !b.hasLink) return;
    final uri = Uri.tryParse(b.targetUrl);
    if (uri == null || uri.scheme != 'https') return;
    unawaited(widget.service.click(b));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    if (b == null || b.imageUrl.isEmpty) {
      return const ColoredBox(color: Colors.white);
    }
    final imageUrl = resolvePublicMediaUrl(
      b.imageUrl,
      categoryHint: 'top-banners',
    );
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: b.hasLink ? open : null,
        child: Image(
            image:
                TopBannerHeaderBackground.debugImageProvider?.call(imageUrl) ??
                    CachedNetworkImageProvider(imageUrl),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Colors.white)));
  }
}
