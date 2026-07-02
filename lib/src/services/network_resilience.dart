import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String kServerUnavailableMessage =
    'Не удалось подключиться к серверу. Проверьте интернет или попробуйте позже.';
const String kNetworkVpnHintMessage =
    'Проверьте интернет-соединение и попробуйте снова.';

bool isNetworkException(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException;
}

bool shouldShowNetworkVpnHint(Object error) {
  if (isNetworkException(error)) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('timeout') ||
      text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('network');
}

Duration _retryDelay(int attempt) {
  if (attempt <= 0) return const Duration(milliseconds: 250);
  if (attempt == 1) return const Duration(milliseconds: 600);
  return const Duration(milliseconds: 1200);
}

class NetworkResilience {
  static Future<T> run<T>(
    Future<T> Function() task, {
    Duration timeout = const Duration(seconds: 12),
    int retries = 0,
    bool retryOnNetworkErrorOnly = true,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await task().timeout(timeout);
      } on TimeoutException catch (e) {
        if (attempt >= retries) rethrow;
        if (kDebugMode) debugPrint('Retry after timeout: $e');
      } on SocketException catch (e) {
        if (attempt >= retries) rethrow;
        if (kDebugMode) debugPrint('Retry after socket error: $e');
      } on http.ClientException catch (e) {
        if (attempt >= retries) rethrow;
        if (kDebugMode) debugPrint('Retry after client error: $e');
      } catch (e) {
        if (!retryOnNetworkErrorOnly && attempt < retries) {
          if (kDebugMode) debugPrint('Retry after generic error: $e');
        } else {
          rethrow;
        }
      }

      await Future<void>.delayed(_retryDelay(attempt));
      attempt += 1;
    }
  }

  static Stream<T> guardStream<T>(
    Stream<T> source, {
    T? fallbackValue,
    void Function(Object error)? onError,
  }) async* {
    try {
      await for (final value in source) {
        yield value;
      }
    } catch (error) {
      onError?.call(error);
      if (fallbackValue != null) {
        yield fallbackValue;
      }
    }
  }
}
