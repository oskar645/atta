/// Prevents brief scroll jitter from repeatedly toggling the map button.
class MapButtonScrollGate {
  MapButtonScrollGate({this.threshold = 18, this.protectedExtent = 320});

  final double threshold;
  final double protectedExtent;
  double _pendingDelta = 0;

  /// Returns `true` to show, `false` to hide, or `null` until movement is clear.
  bool? update(double delta, {double pixels = double.infinity}) {
    // Keep the action visible while the first grid row is still on screen.
    // This also covers pull-to-refresh overscroll, where pixels is negative.
    if (pixels <= protectedExtent) {
      _pendingDelta = 0;
      return true;
    }
    if (delta == 0) return null;

    if (_pendingDelta != 0 && _pendingDelta.sign != delta.sign) {
      _pendingDelta = 0;
    }
    _pendingDelta += delta;
    if (_pendingDelta.abs() < threshold) return null;

    final show = _pendingDelta < 0;
    _pendingDelta = 0;
    return show;
  }
}
