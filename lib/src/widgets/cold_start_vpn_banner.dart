import 'dart:async';

import 'package:flutter/material.dart';

class ColdStartVpnBanner extends StatefulWidget {
  const ColdStartVpnBanner({
    super.key,
    required this.show,
  });

  final bool show;

  @override
  State<ColdStartVpnBanner> createState() => _ColdStartVpnBannerState();
}

class _ColdStartVpnBannerState extends State<ColdStartVpnBanner>
    with SingleTickerProviderStateMixin {
  static const _animationDuration = Duration(milliseconds: 320);
  static const _visibleDuration = Duration(seconds: 4);

  late final AnimationController _controller;
  late final Animation<double> _curvedAnimation;
  Timer? _hideTimer;
  bool _hasStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
      reverseDuration: _animationDuration,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (widget.show) {
      _scheduleShow();
    }
  }

  @override
  void didUpdateWidget(covariant ColdStartVpnBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    if (_hasStarted) return;
    _hasStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.forward();
      _hideTimer = Timer(_visibleDuration, () {
        if (mounted) {
          _controller.reverse();
        }
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1.25),
        end: Offset.zero,
      ).animate(_curvedAnimation),
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.wifi_outlined,
                      size: 19,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ATTA лучше работает без VPN',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Если есть проблемы с загрузкой, отключите VPN',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
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
