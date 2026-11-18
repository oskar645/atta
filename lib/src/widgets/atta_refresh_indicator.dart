import 'dart:math' as math;

import 'package:flutter/material.dart';

const Color kAttaRefreshIndicatorColor = Color(0xFF258FE4);
const double kAttaRefreshIndicatorSize = 24;

/// ATTA's shared pull-to-refresh interaction.
///
/// It keeps Flutter's native refresh gesture and callback behavior while
/// replacing only the stock material disc with a small, background-free arc.
class AttaRefreshIndicator extends StatefulWidget {
  const AttaRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.semanticsLabel,
    this.semanticsValue,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
    this.edgeOffset = 0,
    this.displacement = 40,
    this.onStatusChange,
  });

  final RefreshCallback onRefresh;
  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;
  final String? semanticsLabel;
  final String? semanticsValue;
  final RefreshIndicatorTriggerMode triggerMode;
  final double edgeOffset;
  final double displacement;
  final ValueChanged<RefreshIndicatorStatus?>? onStatusChange;

  @override
  State<AttaRefreshIndicator> createState() => _AttaRefreshIndicatorState();
}

class _AttaRefreshIndicatorState extends State<AttaRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  final ValueNotifier<RefreshIndicatorStatus?> _statusNotifier =
      ValueNotifier<RefreshIndicatorStatus?>(null);
  final ValueNotifier<bool> _userPullNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _rotationController.dispose();
    _statusNotifier.dispose();
    _userPullNotifier.dispose();
    super.dispose();
  }

  bool _trackPullGesture(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) return false;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userPullNotifier.value = false;
      return false;
    }

    final atTop = notification.metrics.extentBefore <= 0.5 ||
        notification.metrics.pixels <=
            notification.metrics.minScrollExtent + 0.5;
    final isPullDown = notification is OverscrollNotification
        ? notification.dragDetails != null && notification.overscroll < -0.5
        : notification is ScrollUpdateNotification
            ? notification.dragDetails != null &&
                (notification.scrollDelta ?? 0) < -0.5
            : false;
    if (atTop && isPullDown) {
      _userPullNotifier.value = true;
    }
    return false;
  }

  void _handleStatusChange(RefreshIndicatorStatus? status) {
    widget.onStatusChange?.call(status);
    // Flutter's noSpinner variant reports `snap` immediately before invoking
    // onRefresh and does not emit a separate `refresh` status afterward.
    if (status == RefreshIndicatorStatus.snap ||
        status == RefreshIndicatorStatus.refresh) {
      _rotationController.repeat();
    } else if (status == RefreshIndicatorStatus.drag) {
      _rotationController
        ..stop()
        ..value = 0;
    } else if (status == RefreshIndicatorStatus.done ||
        status == RefreshIndicatorStatus.canceled ||
        status == null) {
      _rotationController.stop();
      _userPullNotifier.value = false;
    }
    _statusNotifier.value = status;
  }

  bool _isVisible(RefreshIndicatorStatus? status, bool hasUserPull) {
    if (status == RefreshIndicatorStatus.snap ||
        status == RefreshIndicatorStatus.refresh) {
      return true;
    }
    return hasUserPull &&
        (status == RefreshIndicatorStatus.drag ||
            status == RefreshIndicatorStatus.armed);
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.edgeOffset +
        math.max(0, widget.displacement - kAttaRefreshIndicatorSize);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _trackPullGesture,
          child: RefreshIndicator.noSpinner(
            onRefresh: widget.onRefresh,
            onStatusChange: _handleStatusChange,
            notificationPredicate: widget.notificationPredicate,
            semanticsLabel: widget.semanticsLabel,
            semanticsValue: widget.semanticsValue,
            triggerMode: widget.triggerMode,
            elevation: 0,
            child: widget.child,
          ),
        ),
        Positioned(
          top: top,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: ValueListenableBuilder<RefreshIndicatorStatus?>(
                valueListenable: _statusNotifier,
                builder: (context, status, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _userPullNotifier,
                    builder: (context, hasUserPull, _) {
                      return AnimatedOpacity(
                        opacity: _isVisible(status, hasUserPull) ? 1 : 0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: RotationTransition(
                          turns: _rotationController,
                          child: const SizedBox.square(
                            key: ValueKey('atta-refresh-arc'),
                            dimension: kAttaRefreshIndicatorSize,
                            child: CustomPaint(
                              painter: _AttaRefreshArcPainter(),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttaRefreshArcPainter extends CustomPainter {
  const _AttaRefreshArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.2;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final paint = Paint()
      ..color = kAttaRefreshIndicatorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 1.45,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AttaRefreshArcPainter oldDelegate) => false;
}
