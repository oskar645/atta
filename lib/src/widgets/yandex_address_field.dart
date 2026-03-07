import 'dart:async';

import 'package:flutter/material.dart';

import 'package:chestore2/src/services/yandex_suggest_service.dart';

class YandexAddressField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final void Function(String value)? onSelected;

  const YandexAddressField({
    super.key,
    required this.controller,
    this.label = '\u0410\u0434\u0440\u0435\u0441',
    this.onSelected,
  });

  @override
  State<YandexAddressField> createState() => _YandexAddressFieldState();
}

class _YandexAddressFieldState extends State<YandexAddressField> {
  final _service = YandexSuggestService();
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();

  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  bool _loading = false;
  List<YandexAddressSuggestion> _items = [];
  String _rawValue = '';

  @override
  void initState() {
    super.initState();
    _rawValue = widget.controller.text;
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _syncOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onChanged(String value) {
    _rawValue = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _load(value);
    });
    _syncOverlay();
  }

  Future<void> _load(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
      });
      _syncOverlay();
      return;
    }

    setState(() => _loading = true);
    _syncOverlay();
    try {
      final res = await _service.suggest(query);
      if (!mounted) return;
      setState(() => _items = res);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = []);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
      _syncOverlay();
    }
  }

  void _select(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    widget.onSelected?.call(value);
    setState(() {
      _rawValue = value;
      _items = [];
    });
    _removeOverlay();
    _focusNode.unfocus();
  }

  bool _showManualChoice() {
    final raw = _rawValue.trim();
    if (raw.length < 2) return false;
    return !_items.any((x) => x.value.trim().toLowerCase() == raw.toLowerCase());
  }

  bool get _shouldShowOverlay =>
      _focusNode.hasFocus && (_items.isNotEmpty || _showManualChoice());

  void _syncOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!_shouldShowOverlay) {
        _removeOverlay();
        return;
      }

      final overlay = Overlay.maybeOf(context);
      final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (overlay == null || box == null || !box.attached) return;

      if (_overlayEntry == null) {
        _overlayEntry = OverlayEntry(builder: (_) => _buildOverlay());
        overlay.insert(_overlayEntry!);
      } else {
        _overlayEntry!.markNeedsBuild();
      }
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlay() {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      return const SizedBox.shrink();
    }

    final size = box.size;

    return Positioned(
      width: size.width,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: Offset(0, size.height + 4),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: _items.length + (_showManualChoice() ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i < _items.length) {
                  final item = _items[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    subtitle: item.subtitle.trim().isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.subtitle,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.2,
                              ),
                            ),
                          ),
                    onTap: () => _select(item.value),
                  );
                }

                final typed = _rawValue.trim();
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: const Icon(Icons.edit_location_alt_outlined),
                  title: const Text(
                    '\u041e\u0441\u0442\u0430\u0432\u0438\u0442\u044c \u043a\u0430\u043a \u0432\u0432\u0435\u0434\u0435\u043d\u043e',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    typed,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _select(typed),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _fieldKey,
        child: TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).dividerColor,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            isDense: true,
            suffixIcon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          onChanged: _onChanged,
        ),
      ),
    );
  }
}
