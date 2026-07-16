import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

/// Emits a recovery request whenever the system reports a usable connection
/// after an outage or a transport change (Wi-Fi, mobile data, VPN, etc.).
///
/// This service deliberately does not branch on platform: connectivity_plus
/// exposes the same API on iOS and Android.
class NetworkRecoveryService {
  NetworkRecoveryService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final StreamController<void> _recoveries = StreamController<void>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  List<ConnectivityResult>? _lastResults;
  bool _started = false;

  Stream<void> get recoveries => _recoveries.stream;

  Future<void> start() async {
    if (_started) return;
    try {
      _lastResults = await _connectivity.checkConnectivity();
      _subscription = _connectivity.onConnectivityChanged.listen(
        _onChanged,
        onError: (_, __) {},
      );
      _started = true;
    } on MissingPluginException {
      // A hot restart cannot load a newly added native plugin into the old
      // process. Lifecycle-based recovery remains available until a full run.
    } on PlatformException {
      // Network recovery is an enhancement and must never break app startup.
    }
  }

  void _onChanged(List<ConnectivityResult> results) {
    final previous = _lastResults;
    _lastResults = results;
    if (!_hasUsableConnection(results)) return;

    // A transition from offline, or between transports, invalidates open HTTP
    // connections and WebSockets even if the OS keeps the app alive.
    if (previous == null ||
        !_hasUsableConnection(previous) ||
        !_sameResults(previous, results)) {
      _recoveries.add(null);
    }
  }

  bool _hasUsableConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _sameResults(
    List<ConnectivityResult> first,
    List<ConnectivityResult> second,
  ) {
    if (first.length != second.length) return false;
    return first.toSet().containsAll(second);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _recoveries.close();
  }
}
