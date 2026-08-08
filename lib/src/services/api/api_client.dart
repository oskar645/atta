import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:atta/src/services/api/api_config.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

typedef ApiRefreshHandler = Future<bool> Function();
typedef ApiSessionExpiredHandler = Future<void> Function();
typedef ApiAuthorizedSessionWaiter = Future<void> Function();
typedef ApiAccountBlockedHandler = Future<void> Function();

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    http.Client? httpClient,
  })  : _tokenStorage = tokenStorage,
        _httpClient = httpClient ?? http.Client();

  final TokenStorage _tokenStorage;
  final http.Client _httpClient;

  static ApiRefreshHandler? _refreshHandler;
  static ApiSessionExpiredHandler? _sessionExpiredHandler;
  static ApiAuthorizedSessionWaiter? _authorizedSessionWaiter;
  static ApiAccountBlockedHandler? _accountBlockedHandler;
  static Future<bool>? _refreshInFlight;
  int _requestSequence = 0;

  static void configureAuthHandlers({
    ApiRefreshHandler? onRefreshSession,
    ApiSessionExpiredHandler? onSessionExpired,
    ApiAuthorizedSessionWaiter? onAwaitAuthorizedSession,
    ApiAccountBlockedHandler? onAccountBlocked,
  }) {
    _refreshHandler = onRefreshSession;
    _sessionExpiredHandler = onSessionExpired;
    _authorizedSessionWaiter = onAwaitAuthorizedSession;
    _accountBlockedHandler = onAccountBlocked;
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool authorized = false,
    bool sendAuthIfAvailable = false,
  }) {
    return _send(
      'GET',
      path,
      queryParameters: queryParameters,
      authorized: authorized,
      sendAuthIfAvailable: sendAuthIfAvailable,
    );
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    bool authorized = false,
  }) {
    return _send(
      'POST',
      path,
      body: body,
      authorized: authorized,
    );
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    bool authorized = false,
  }) {
    return _send(
      'PATCH',
      path,
      body: body,
      authorized: authorized,
    );
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    bool authorized = false,
  }) {
    return _send(
      'PUT',
      path,
      body: body,
      authorized: authorized,
    );
  }

  Future<dynamic> delete(
    String path, {
    Object? body,
    bool authorized = false,
  }) {
    return _send(
      'DELETE',
      path,
      body: body,
      authorized: authorized,
    );
  }

  Future<dynamic> postMultipart(
    String path, {
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    String fieldName = 'file',
    Map<String, String>? fields,
    bool authorized = false,
    bool allowAuthRetry = true,
  }) async {
    if (authorized) {
      await _awaitAuthorizedSessionReady();
    }
    if (authorized) {
      await _awaitActiveRefreshIfAny();
    }
    if (authorized) {
      final token = await _tokenStorage.readAccessToken();
      if (token == null || token.trim().isEmpty) {
        throw const ApiException(
          'Требуется авторизация',
          statusCode: 401,
          code: 'local_unauthorized',
        );
      }
    }

    final uri = ApiConfig.uri(path);
    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields ?? const <String, String>{})
      ..files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ),
      );

    if (authorized) {
      final token = await _tokenStorage.readAccessToken();
      request.headers['Authorization'] = 'Bearer ${token!.trim()}';
    }
    request.headers['Accept'] = 'application/json';

    _logRequest(
      'POST',
      uri,
      authorized: authorized,
      requestId: 'multipart-${++_requestSequence}',
    );

    try {
      final streamed =
          await _httpClient.send(request).timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      _logResponse(
        'POST',
        uri,
        response.statusCode,
        requestId: 'multipart-$_requestSequence',
      );
      if (authorized &&
          response.statusCode == 401 &&
          allowAuthRetry &&
          !_shouldSkipAuthRefresh(path)) {
        final refreshed = await _tryRefreshSession();
        if (refreshed) {
          return postMultipart(
            path,
            bytes: bytes,
            fileName: fileName,
            contentType: contentType,
            fieldName: fieldName,
            fields: fields,
            authorized: authorized,
            allowAuthRetry: false,
          );
        }
      }
      return _decodeResponse(response);
    } on TimeoutException catch (error) {
      throw ApiException(kNetworkVpnHintMessage,
          code: 'timeout', details: error);
    } on http.ClientException catch (error) {
      throw ApiException(kNetworkVpnHintMessage,
          code: 'network', details: error);
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? body,
    bool authorized = false,
    bool sendAuthIfAvailable = false,
    bool allowAuthRetry = true,
    int networkRetryAttempt = 0,
    String? requestId,
  }) async {
    final id = requestId ?? 'private-${++_requestSequence}';
    final isPrivate = authorized || sendAuthIfAvailable;
    if (isPrivate) {
      _logPrivate('PrivateRequest start endpoint=$path requestId=$id');
    }
    try {
      if (authorized || sendAuthIfAvailable) {
        _logPrivate('AuthGate wait requestId=$id');
        await _awaitAuthorizedSessionReady();
        _logPrivate('AuthGate passed requestId=$id');
      }
      if (authorized || sendAuthIfAvailable) {
        await _awaitActiveRefreshIfAny();
      }
      if (authorized) {
        final token = await _tokenStorage.readAccessToken();
        if (token == null || token.trim().isEmpty) {
          throw const ApiException(
            'Требуется авторизация',
            statusCode: 401,
            code: 'local_unauthorized',
          );
        }
      }

      final uri = ApiConfig.uri(path, queryParameters);
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

      if (authorized || sendAuthIfAvailable) {
        final token = await _tokenStorage.readAccessToken();
        if (token != null && token.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer ${token.trim()}';
        }
      }

      _logRequest(method, uri, authorized: authorized, requestId: id);
      if (isPrivate) {
        _logPrivate('HTTP send requestId=$id endpoint=$path');
      }

      final response = await _dispatch(
        method,
        uri,
        headers,
        body,
      ).timeout(ApiConfig.requestTimeout);

      _logResponse(method, uri, response.statusCode, requestId: id);
      if (isPrivate) {
        _logPrivate(
            'HTTP response requestId=$id status=${response.statusCode}');
      }
      if ((authorized || sendAuthIfAvailable) &&
          response.statusCode == 401 &&
          allowAuthRetry &&
          !_shouldSkipAuthRefresh(path)) {
        final refreshed = await _tryRefreshSession();
        if (refreshed) {
          return _send(
            method,
            path,
            queryParameters: queryParameters,
            body: body,
            authorized: authorized,
            sendAuthIfAvailable: sendAuthIfAvailable,
            allowAuthRetry: false,
            networkRetryAttempt: networkRetryAttempt,
            requestId: id,
          );
        }
      }
      late final dynamic decoded;
      try {
        decoded = _decodeResponse(response);
      } on ApiException catch (error) {
        if ((authorized || sendAuthIfAvailable) &&
            error.code == 'ACCOUNT_BLOCKED') {
          await _accountBlockedHandler?.call();
        }
        rethrow;
      }
      if (isPrivate) {
        _logPrivate('PrivateRequest complete requestId=$id');
      }
      return decoded;
    } on TimeoutException catch (error) {
      if (_shouldRetryNetwork(method) &&
          networkRetryAttempt < _networkRetryDelays.length) {
        await Future<void>.delayed(_networkRetryDelays[networkRetryAttempt]);
        return _send(
          method,
          path,
          queryParameters: queryParameters,
          body: body,
          authorized: authorized,
          sendAuthIfAvailable: sendAuthIfAvailable,
          allowAuthRetry: allowAuthRetry,
          networkRetryAttempt: networkRetryAttempt + 1,
          requestId: id,
        );
      }
      throw ApiException(kNetworkVpnHintMessage,
          code: 'timeout', details: error);
    } on SocketException catch (error) {
      if (_shouldRetryNetwork(method) &&
          networkRetryAttempt < _networkRetryDelays.length) {
        await Future<void>.delayed(_networkRetryDelays[networkRetryAttempt]);
        return _send(
          method,
          path,
          queryParameters: queryParameters,
          body: body,
          authorized: authorized,
          sendAuthIfAvailable: sendAuthIfAvailable,
          allowAuthRetry: allowAuthRetry,
          networkRetryAttempt: networkRetryAttempt + 1,
          requestId: id,
        );
      }
      throw ApiException(kNetworkVpnHintMessage,
          code: 'network', details: error);
    } on http.ClientException catch (error) {
      if (_shouldRetryNetwork(method) &&
          networkRetryAttempt < _networkRetryDelays.length) {
        await Future<void>.delayed(_networkRetryDelays[networkRetryAttempt]);
        return _send(
          method,
          path,
          queryParameters: queryParameters,
          body: body,
          authorized: authorized,
          sendAuthIfAvailable: sendAuthIfAvailable,
          allowAuthRetry: allowAuthRetry,
          networkRetryAttempt: networkRetryAttempt + 1,
          requestId: id,
        );
      }
      throw ApiException(kNetworkVpnHintMessage,
          code: 'network', details: error);
    } finally {
      if (isPrivate) {
        _logPrivate('PrivateRequest finally requestId=$id');
      }
    }
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    final encodedBody = body == null ? null : jsonEncode(body);

    switch (method) {
      case 'GET':
        return _httpClient.get(uri, headers: headers);
      case 'POST':
        return _httpClient.post(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return _httpClient.patch(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return _httpClient.put(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return _httpClient.delete(uri, headers: headers, body: encodedBody);
      default:
        throw ApiException('Unsupported HTTP method: $method');
    }
  }

  dynamic _decodeResponse(http.Response response) {
    final rawBody = response.body.trim();
    dynamic decoded;
    if (rawBody.isNotEmpty) {
      try {
        decoded = jsonDecode(rawBody);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 413) {
      throw const ApiException(
        'Файл слишком большой. Выберите изображение меньшего размера.',
        statusCode: 413,
        code: 'payload_too_large',
      );
    }

    if (response.statusCode == 500 || response.statusCode == 503) {
      throw ApiException(
        'Сервис временно недоступен. Попробуйте позже.',
        statusCode: response.statusCode,
        code: 'server_unavailable',
        details: rawBody,
      );
    }

    final errorMap = decoded is Map<String, dynamic> ? decoded : null;
    final message = (errorMap?['message'] ??
            errorMap?['error'] ??
            'Ошибка запроса к серверу')
        .toString()
        .trim();

    throw ApiException(
      message.isEmpty ? 'Ошибка запроса к серверу' : message,
      statusCode: response.statusCode,
      code: errorMap?['code']?.toString(),
      details: errorMap ?? rawBody,
    );
  }

  void _logRequest(
    String method,
    Uri uri, {
    required bool authorized,
    required String requestId,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[ApiClient] $method ${uri.path} auth=${authorized ? 'bearer' : 'none'} requestId=$requestId',
    );
  }

  void _logResponse(String method, Uri uri, int statusCode,
      {required String requestId}) {
    if (!kDebugMode) return;
    debugPrint(
        '[ApiClient] $method ${uri.path} -> $statusCode requestId=$requestId');
  }

  void _logPrivate(String message) {
    if (kDebugMode) debugPrint('[ApiClient] $message');
  }

  // Retrying reads is safe and is enough for every screen refresh. Mutating
  // requests are deliberately not retried here: after a network switch their
  // result may have reached the server even when the response did not.
  static const List<Duration> _networkRetryDelays = <Duration>[
    Duration(milliseconds: 350),
  ];

  bool _shouldRetryNetwork(String method) => method == 'GET';

  bool _shouldSkipAuthRefresh(String path) {
    return path == '/auth/refresh' ||
        path == '/auth/login' ||
        path == '/auth/login-phone' ||
        path == '/auth/signup' ||
        path == '/auth/signup-phone' ||
        path == '/auth/logout';
  }

  Future<bool> _tryRefreshSession() async {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final future = _performRefreshSession().then(_resolveRefreshOutcome,
        onError: (_) => _resolveRefreshOutcome(false));
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _performRefreshSession() async {
    final refreshHandler = _refreshHandler;
    if (refreshHandler == null) {
      return false;
    }
    try {
      return await refreshHandler();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _resolveRefreshOutcome(bool refreshed) async {
    if (refreshed) {
      return true;
    }
    await _sessionExpiredHandler?.call();
    throw const ApiException(
      'Сессия истекла. Войдите снова.',
      statusCode: 401,
      code: 'session_expired',
    );
  }

  Future<void> _awaitActiveRefreshIfAny() async {
    final refreshFuture = _refreshInFlight;
    if (refreshFuture == null) {
      return;
    }
    await refreshFuture;
  }

  Future<void> _awaitAuthorizedSessionReady() async {
    final waiter = _authorizedSessionWaiter;
    if (waiter == null) {
      return;
    }
    await waiter();
  }
}
