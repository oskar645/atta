import 'dart:io';

import 'package:atta/src/utils/media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PhotoViewerScreen extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.photoUrls,
    this.initialIndex = 0,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex.clamp(0, widget.photoUrls.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_page + 1}/${widget.photoUrls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photoUrls.length,
        onPageChanged: (index) => setState(() => _page = index),
        itemBuilder: (_, i) {
          final rawUrl = widget.photoUrls[i];
          final url = resolvePublicMediaUrl(rawUrl);
          final localPath = url.startsWith('file://')
              ? url.replaceFirst('file://', '')
              : (rawUrl.startsWith('/') ? rawUrl : null);
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: localPath != null
                  ? Image.file(
                      File(localPath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 52,
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      errorWidget: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 52,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
