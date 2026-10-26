import 'dart:async';

import 'package:atta/src/models/listing.dart';
import 'package:atta/src/services/listings_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef ListingVideoChanged = void Function(
  ListingVideo? video,
  bool hasUnresolvedText,
);

class ListingVideoField extends StatefulWidget {
  const ListingVideoField({
    super.key,
    this.initialVideo,
    required this.onChanged,
    this.enabled = true,
  });

  final ListingVideo? initialVideo;
  final ListingVideoChanged onChanged;
  final bool enabled;

  @override
  State<ListingVideoField> createState() => _ListingVideoFieldState();
}

class _ListingVideoFieldState extends State<ListingVideoField> {
  late final TextEditingController _controller;
  Timer? _debounce;
  ListingVideo? _video;
  String? _error;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _video = widget.initialVideo;
    _controller = TextEditingController(text: _video?.originalUrl ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String raw) {
    _debounce?.cancel();
    final text = raw.trim();
    final request = ++_request;
    setState(() {
      _video = null;
      _error = null;
      _loading = text.isNotEmpty;
    });
    widget.onChanged(null, text.isNotEmpty);
    if (text.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final video =
            await context.read<ListingsService>().resolveListingVideo(text);
        if (!mounted || request != _request) return;
        setState(() {
          _video = video;
          _loading = false;
        });
        widget.onChanged(video, false);
      } catch (_) {
        if (!mounted || request != _request) return;
        setState(() {
          _error = 'Не удалось открыть видео. Проверьте ссылку.';
          _loading = false;
        });
      }
    });
  }

  void _clear() {
    _request++;
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _video = null;
      _error = null;
      _loading = false;
    });
    widget.onChanged(null, false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Видео с Rutube или VK Видео',
          key: const ValueKey('listing_video_helper_title'),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
        ),
        TextField(
          key: const ValueKey('listing_video_url_field'),
          controller: _controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: true,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          contextMenuBuilder: (context, editableTextState) =>
              AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          ),
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: 'Ссылка на видео',
            errorText: _error,
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _controller.text.trim().isNotEmpty
                    ? IconButton(
                        tooltip: 'Удалить видео',
                        onPressed: widget.enabled ? _clear : null,
                        icon: const Icon(Icons.close),
                      )
                    : null,
          ),
        ),
        if (_video != null) ...[
          const SizedBox(height: 10),
          SizedBox.square(
            key: const ValueKey('listing_video_preview'),
            dimension: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _video!.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                  const Center(
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
