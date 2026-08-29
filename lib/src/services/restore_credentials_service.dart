import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RestoreCredentialStatus {
  success,
  notAvailable,
  error,
}

class RestoreCredentialResult {
  const RestoreCredentialResult({
    required this.status,
    this.responseJson,
    this.reason,
    this.cloudBackupEnabled,
  });

  final RestoreCredentialStatus status;
  final Map<String, dynamic>? responseJson;
  final String? reason;
  final bool? cloudBackupEnabled;

  bool get isSuccess => status == RestoreCredentialStatus.success;
}

class RestoreCredentialsService {
  const RestoreCredentialsService({
    MethodChannel channel = const MethodChannel('atta/restore_credentials'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<RestoreCredentialResult> create(
    Map<String, dynamic> requestJson,
  ) async {
    if (!isAndroidRuntime) {
      return const RestoreCredentialResult(
        status: RestoreCredentialStatus.notAvailable,
        reason: 'not_android',
      );
    }
    return _invoke(
      'create',
      {'requestJson': jsonEncode(requestJson)},
    );
  }

  Future<RestoreCredentialResult> get(
    Map<String, dynamic> requestJson,
  ) async {
    if (!isAndroidRuntime) {
      return const RestoreCredentialResult(
        status: RestoreCredentialStatus.notAvailable,
        reason: 'not_android',
      );
    }
    return _invoke(
      'get',
      {'requestJson': jsonEncode(requestJson)},
    );
  }

  Future<RestoreCredentialResult> clear() async {
    if (!isAndroidRuntime) {
      return const RestoreCredentialResult(
        status: RestoreCredentialStatus.notAvailable,
        reason: 'not_android',
      );
    }
    return _invoke('clear');
  }

  Future<RestoreCredentialResult> _invoke(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        method,
        arguments,
      );
      final response = Map<String, dynamic>.from(raw ?? const {});
      final status = response['status'] == 'success'
          ? RestoreCredentialStatus.success
          : response['status'] == 'notAvailable'
              ? RestoreCredentialStatus.notAvailable
              : RestoreCredentialStatus.error;
      return RestoreCredentialResult(
        status: status,
        responseJson: _decodeResponseJson(response['responseJson']),
        reason: (response['reason'] ?? response['code'] ?? response['message'])
            ?.toString(),
        cloudBackupEnabled: response['cloudBackupEnabled'] is bool
            ? response['cloudBackupEnabled'] as bool
            : null,
      );
    } on MissingPluginException {
      return const RestoreCredentialResult(
        status: RestoreCredentialStatus.notAvailable,
        reason: 'missing_plugin',
      );
    } on PlatformException catch (error) {
      return RestoreCredentialResult(
        status: RestoreCredentialStatus.error,
        reason: error.code,
      );
    }
  }

  Map<String, dynamic>? _decodeResponseJson(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(decoded);
  }
}
