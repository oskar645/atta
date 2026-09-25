import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A separate, atomic secure record; never shares session storage keys.
class PendingPasswordlessStorage {
  static const key = 'atta_pending_passwordless_v1';
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  static Future<void>? _writes;

  Future<void> _enqueue(Future<void> Function() action) {
    final next = (_writes ?? Future<void>.value()).then((_) => action());
    final settled = next.then<void>((_) {}, onError: (Object _) {});
    _writes = settled;
    unawaited(settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    }));
    return next;
  }

  Future<void> save(Map<String, dynamic> state) {
    final encoded = jsonEncode(state);
    return _enqueue(() => _secure.write(key: key, value: encoded));
  }

  Future<void> clear() => _enqueue(() => _secure.delete(key: key));

  Future<Map<String, dynamic>?> read() async {
    await _writes;
    final raw = await _secure.read(key: key);
    if (raw == null) return null;
    try {
      final state = jsonDecode(raw) as Map<String, dynamic>;
      if (state['challenge'] is! String ||
          (state['challenge'] as String).isEmpty ||
          state['phone'] is! String ||
          state['callToPhone'] is! String ||
          DateTime.tryParse('${state['expiresAt']}') == null ||
          (state['registrationToken'] != null &&
              state['registrationToken'] is! String)) {
        throw const FormatException();
      }
      return state;
    } catch (_) {
      await clear();
      return null;
    }
  }
}
