import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/api_exception.dart';
import 'package:atta/src/services/api/support_api.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/network_resilience.dart';
import 'package:atta/src/utils/media_url.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SupportService {
  SupportService({
    SupportApi? api,
    Duration messagePollInterval = const Duration(seconds: 45),
    Duration adminPollInterval = const Duration(seconds: 45),
  })  : _api = api ?? SupportApi(_apiClient),
        _messagePollInterval = messagePollInterval,
        _adminPollInterval = adminPollInterval;

  final Uuid _uuid = const Uuid();
  final SupportApi _api;
  final Duration _messagePollInterval;
  final Duration _adminPollInterval;
  final Map<String, List<Map<String, dynamic>>> _messageCache =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, StreamController<List<Map<String, dynamic>>>>
      _messageControllers =
      <String, StreamController<List<Map<String, dynamic>>>>{};
  final Map<String, Stream<List<Map<String, dynamic>>>> _messageStreams =
      <String, Stream<List<Map<String, dynamic>>>>{};
  final Map<String, int> _messageListenerCounts = <String, int>{};
  final Map<String, Timer> _messagePollers = <String, Timer>{};
  final Map<String, bool> _ticketUsesAdminEndpoint = <String, bool>{};
  final Map<String, Future<List<Map<String, dynamic>>>>
      _messageRefreshInFlight = <String, Future<List<Map<String, dynamic>>>>{};
  final Set<String> _missingTicketIds = <String>{};
  List<Map<String, dynamic>> _adminTicketsCache =
      const <Map<String, dynamic>>[];
  StreamController<List<Map<String, dynamic>>>? _adminTicketsController;
  Timer? _adminTicketsPoller;
  bool _adminSessionActive = false;
  Future<List<Map<String, dynamic>>>? _adminTicketsInFlight;
  DateTime? _lastAdminTicketsRefreshAt;

  static final TokenStorage _tokenStorage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _tokenStorage);
  static const Duration _adminTicketsCacheTtl = Duration(seconds: 20);
  static const String _hiddenAdminTicketsPrefsKeyPrefix =
      'support_hidden_admin_tickets_v1';
  Map<String, String> _hiddenAdminTickets = <String, String>{};
  String? _hiddenAdminTicketsOwnerUid;

  void activateAdminSession({required bool isAdmin}) {
    _adminSessionActive = isAdmin;
    if (!isAdmin) {
      _resetAdminState();
    }
  }

  void resetSession() {
    for (final poller in _messagePollers.values) {
      poller.cancel();
    }
    _messagePollers.clear();
    _messageStreams.clear();
    _messageListenerCounts.clear();
    _ticketUsesAdminEndpoint.clear();
    _messageCache.clear();
    _missingTicketIds.clear();
    _adminTicketsPoller?.cancel();
    _adminTicketsPoller = null;
    _resetAdminState();
    _adminSessionActive = false;
    _hiddenAdminTickets = <String, String>{};
    _hiddenAdminTicketsOwnerUid = null;
  }

  List<Map<String, dynamic>> peekMessages(String ticketId) {
    return List<Map<String, dynamic>>.from(
      _messageCache[ticketId] ?? const <Map<String, dynamic>>[],
    );
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> response) {
    final raw = response['items'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map(_normalizeMessageMap).toList();
  }

  void _debugSource(String message) {
    if (!kDebugMode ||
        message == 'Support source: Timeweb' ||
        message ==
            'Support source: Timeweb admin unauthorized, resetting state') {
      return;
    }
    debugPrint(message);
  }

  Future<String?> getOrCreateMyTicketId({required String uid}) async {
    _debugSource('Support source: Timeweb');
    final response = await _api.listMyTickets();
    final items = _extractItems(response);
    if (items.isEmpty) return null;
    return (items.first['id'] ?? '').toString();
  }

  Future<String> createTicketAndSendFirstMessage({
    required String uid,
    required String name,
    required String text,
    File? imageFile,
  }) async {
    _debugSource('Support source: Timeweb');
    final optimisticImageUrl =
        imageFile == null ? '' : 'file://${imageFile.path}';
    final uploadedImageUrl = await _uploadImageIfNeeded(imageFile);
    final response = await _api.createTicket(
      name: name,
      text: text,
      imageUrl: uploadedImageUrl.isEmpty ? null : uploadedImageUrl,
    );
    final rawTicket = response['ticket'];
    final ticketId =
        (rawTicket is Map ? rawTicket['id'] : null)?.toString() ?? '';
    if (ticketId.isNotEmpty) {
      final items = _extractItems(response);
      final seeded = items.isNotEmpty
          ? items
          : <Map<String, dynamic>>[
              _buildOptimisticMessage(
                ticketId: ticketId,
                text: text,
                sender: 'user',
                imageUrl: optimisticImageUrl,
              ),
            ];
      _publishMessages(ticketId, seeded);
    }
    return ticketId;
  }

  Future<void> sendMessage({
    required String ticketId,
    required String text,
    File? imageFile,
    String? existingMessageId,
  }) async {
    _debugSource('Support source: Timeweb');
    final localImageUrl = imageFile == null ? '' : 'file://${imageFile.path}';
    final localMessageId = (existingMessageId ?? '').trim();
    final optimistic = _buildOptimisticMessage(
      ticketId: ticketId,
      text: text,
      sender: 'user',
      imageUrl: localImageUrl,
      localImagePath: imageFile?.path,
      messageId: localMessageId.isEmpty ? null : localMessageId,
    );
    final currentMessages =
        _messageCache[ticketId] ?? const <Map<String, dynamic>>[];
    _publishMessages(
      ticketId,
      localMessageId.isEmpty
          ? _mergeMessages(
              currentMessages,
              <Map<String, dynamic>>[optimistic],
            )
          : currentMessages
              .map((item) => (item['id'] ?? '').toString() == localMessageId
                  ? optimistic
                  : item)
              .toList(),
    );
    try {
      final uploadedImageUrl = await _uploadImageIfNeeded(
        imageFile,
        ticketId: ticketId,
      );
      final response = await _api.sendMessage(
        ticketId: ticketId,
        text: text,
        imageUrl: uploadedImageUrl.isEmpty ? null : uploadedImageUrl,
      );
      final item = response['item'];
      if (item is Map) {
        _publishMessages(
          ticketId,
          _mergeMessages(
            _messageCache[ticketId] ?? const <Map<String, dynamic>>[],
            <Map<String, dynamic>>[
              _normalizeMessageMap(item),
            ],
            removedIds: <String>{optimistic['id'].toString(), localMessageId},
          ),
        );
      }
    } catch (error) {
      _markMessageFailed(
        ticketId,
        optimistic['id'].toString(),
        _messageErrorText(error),
      );
      rethrow;
    }
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String ticketId) {
    return _streamMessages(ticketId, useAdminEndpoint: false);
  }

  Stream<List<Map<String, dynamic>>> streamAdminMessages(String ticketId) {
    return _streamMessages(ticketId, useAdminEndpoint: true);
  }

  Stream<List<Map<String, dynamic>>> _streamMessages(
    String ticketId, {
    required bool useAdminEndpoint,
  }) {
    _debugSource('Support source: Timeweb');
    final normalizedTicketId = ticketId.trim();
    if (normalizedTicketId.isEmpty ||
        _missingTicketIds.contains(normalizedTicketId)) {
      return Stream<List<Map<String, dynamic>>>.value(
        List<Map<String, dynamic>>.from(
          _messageCache[normalizedTicketId] ?? const <Map<String, dynamic>>[],
        ),
      );
    }
    _ticketUsesAdminEndpoint[normalizedTicketId] = useAdminEndpoint;
    final streamKey =
        '${useAdminEndpoint ? 'admin' : 'user'}:$normalizedTicketId';
    return _messageStreams.putIfAbsent(
      streamKey,
      () => Stream<List<Map<String, dynamic>>>.multi((streamController) {
        final controller = _messageControllerFor(normalizedTicketId);
        StreamSubscription<List<Map<String, dynamic>>>? sub;
        var disposed = false;

        void pushCached() {
          final cached = _messageCache[normalizedTicketId];
          if (cached != null && !disposed) {
            streamController.add(List<Map<String, dynamic>>.from(cached));
          }
        }

        Future<void> refreshInitial() async {
          try {
            final items = useAdminEndpoint
                ? await refreshAdminMessages(normalizedTicketId)
                : await refreshMessages(normalizedTicketId);
            if (!disposed) {
              streamController.add(List<Map<String, dynamic>>.from(items));
            }
          } catch (error) {
            if (!disposed) {
              streamController.addError(error);
            }
          }
        }

        _messageListenerCounts[normalizedTicketId] =
            (_messageListenerCounts[normalizedTicketId] ?? 0) + 1;
        _ensureMessagePolling(normalizedTicketId);
        pushCached();
        if (!_messageCache.containsKey(normalizedTicketId)) {
          unawaited(refreshInitial());
        }
        sub = controller.stream.listen(
          (items) {
            if (!disposed) {
              streamController.add(List<Map<String, dynamic>>.from(items));
            }
          },
          onError: streamController.addError,
        );

        streamController.onCancel = () async {
          disposed = true;
          await sub?.cancel();
          final remaining =
              (_messageListenerCounts[normalizedTicketId] ?? 1) - 1;
          if (remaining <= 0) {
            _messageListenerCounts.remove(normalizedTicketId);
            _stopMessagePolling(normalizedTicketId);
          } else {
            _messageListenerCounts[normalizedTicketId] = remaining;
          }
        };
      }).asBroadcastStream(
        onCancel: (subscription) => subscription.cancel(),
      ),
    );
  }

  Stream<List<Map<String, dynamic>>> streamTicketsForAdmin() {
    if (!_adminSessionActive) {
      _resetAdminState();
      return Stream<List<Map<String, dynamic>>>.value(
        const <Map<String, dynamic>>[],
      );
    }
    final controller = _adminTicketsControllerFor();
    if (_adminTicketsCache.isEmpty || _isAdminTicketsRefreshStale()) {
      unawaited(refreshAdminTickets(force: _adminTicketsCache.isEmpty));
    }
    return Stream<List<Map<String, dynamic>>>.multi((streamController) {
      streamController.add(List<Map<String, dynamic>>.from(_adminTicketsCache));
      final sub = controller.stream.listen(
        streamController.add,
        onError: streamController.addError,
      );
      streamController.onCancel = () async {
        await sub.cancel();
      };
    });
  }

  Future<void> hideAdminTicket({
    required String ticketId,
    required String updatedAt,
  }) async {
    final normalizedTicketId = ticketId.trim();
    final normalizedUpdatedAt = updatedAt.trim();
    if (normalizedTicketId.isEmpty || normalizedUpdatedAt.isEmpty) {
      return;
    }

    await _loadHiddenAdminTickets();
    _hiddenAdminTickets[normalizedTicketId] = normalizedUpdatedAt;
    await _saveHiddenAdminTickets();

    _adminTicketsCache = _adminTicketsCache
        .where(
          (item) => (item['id'] ?? '').toString().trim() != normalizedTicketId,
        )
        .toList(growable: false);
    _lastAdminTicketsRefreshAt = DateTime.now();
    _adminTicketsControllerFor()
        .add(List<Map<String, dynamic>>.from(_adminTicketsCache));
  }

  Future<void> adminReply({
    required String ticketId,
    required String text,
  }) async {
    _debugSource('Support source: Timeweb');
    final optimistic = _buildOptimisticMessage(
      ticketId: ticketId,
      text: text,
      sender: 'admin',
    );
    _publishMessages(
      ticketId,
      _mergeMessages(_messageCache[ticketId] ?? const <Map<String, dynamic>>[],
          <Map<String, dynamic>>[optimistic]),
    );
    try {
      final response =
          await _api.adminSendMessage(ticketId: ticketId, text: text);
      final item = response['item'];
      if (item is Map) {
        _publishMessages(
          ticketId,
          _mergeMessages(
            _messageCache[ticketId] ?? const <Map<String, dynamic>>[],
            <Map<String, dynamic>>[_normalizeMessageMap(item)],
            removedIds: <String>{optimistic['id'].toString()},
          ),
        );
      }
    } catch (error) {
      _markMessageFailed(
        ticketId,
        optimistic['id'].toString(),
        _messageErrorText(error),
      );
      rethrow;
    }
  }

  Future<void> retryMessage({
    required String ticketId,
    required String messageId,
  }) async {
    final current = _messageCache[ticketId] ?? const <Map<String, dynamic>>[];
    final target = current.cast<Map<String, dynamic>>().firstWhere(
          (item) => (item['id'] ?? '').toString() == messageId,
          orElse: () => <String, dynamic>{},
        );
    final text = (target['text'] ?? '').toString().trim();
    final localImagePath = (target['local_image_path'] ?? '').toString().trim();
    final hasImage = (target['image_url'] ?? '').toString().trim().isNotEmpty ||
        localImagePath.isNotEmpty;
    if (text.isEmpty && !hasImage) return;
    final sender = (target['sender'] ?? 'user').toString();
    _publishMessages(
      ticketId,
      current
          .map((item) => (item['id'] ?? '').toString() == messageId
              ? <String, dynamic>{
                  ...item,
                  'local_status': 'pending',
                  'error_text': null,
                }
              : item)
          .toList(),
    );
    if (sender == 'admin') {
      await adminReply(ticketId: ticketId, text: text);
      return;
    }
    await sendMessage(
      ticketId: ticketId,
      text: text,
      imageFile: localImagePath.isEmpty ? null : File(localImagePath),
      existingMessageId: messageId,
    );
  }

  Future<void> markReadByAdmin(String ticketId) async {
    _debugSource('Support source: Timeweb');
  }

  Future<List<Map<String, dynamic>>> refreshMessages(String ticketId) async {
    return _refreshMessages(ticketId, useAdminEndpoint: false);
  }

  Future<List<Map<String, dynamic>>> refreshAdminMessages(
    String ticketId,
  ) async {
    return _refreshMessages(ticketId, useAdminEndpoint: true);
  }

  Future<List<Map<String, dynamic>>> _refreshMessages(
    String ticketId, {
    required bool useAdminEndpoint,
  }) async {
    final normalizedTicketId = ticketId.trim();
    if (normalizedTicketId.isEmpty) return const <Map<String, dynamic>>[];
    if (_missingTicketIds.contains(normalizedTicketId)) {
      return List<Map<String, dynamic>>.from(
        _messageCache[normalizedTicketId] ?? const <Map<String, dynamic>>[],
      );
    }
    final existing = _messageRefreshInFlight[normalizedTicketId];
    if (existing != null) {
      return existing;
    }
    _ticketUsesAdminEndpoint[normalizedTicketId] = useAdminEndpoint;
    final future = () async {
      try {
        final response = useAdminEndpoint
            ? await _api.adminTicket(normalizedTicketId)
            : await _api.getTicket(normalizedTicketId);
        final items = _extractItems(response);
        _missingTicketIds.remove(normalizedTicketId);
        _ticketUsesAdminEndpoint[normalizedTicketId] = useAdminEndpoint;
        _publishMessages(
          normalizedTicketId,
          _mergeMessages(
            _messageCache[normalizedTicketId] ?? const <Map<String, dynamic>>[],
            items,
          ),
        );
        return List<Map<String, dynamic>>.from(
          _messageCache[normalizedTicketId] ?? items,
        );
      } catch (error) {
        if (error is ApiException && error.isNotFound) {
          _debugSource(
            'Support source: ticket $normalizedTicketId not found, stopping polling',
          );
          _missingTicketIds.add(normalizedTicketId);
          _stopMessagePolling(normalizedTicketId);
          return List<Map<String, dynamic>>.from(
            _messageCache[normalizedTicketId] ?? const <Map<String, dynamic>>[],
          );
        }
        rethrow;
      }
    }();
    _messageRefreshInFlight[normalizedTicketId] = future;
    try {
      return await future;
    } finally {
      if (identical(_messageRefreshInFlight[normalizedTicketId], future)) {
        _messageRefreshInFlight.remove(normalizedTicketId);
      }
    }
  }

  Future<List<Map<String, dynamic>>> refreshAdminTickets({
    bool force = false,
  }) async {
    if (!await _canUseAdminEndpoints()) {
      _resetAdminState();
      return const <Map<String, dynamic>>[];
    }
    if (!force &&
        !_isAdminTicketsRefreshStale() &&
        _adminTicketsCache.isNotEmpty) {
      return List<Map<String, dynamic>>.from(_adminTicketsCache);
    }
    final existing = _adminTicketsInFlight;
    if (existing != null) {
      return existing;
    }

    final future = () async {
      final response = await _api.adminList();
      final items = await _filterHiddenAdminTickets(_extractItems(response));
      _adminTicketsCache = List<Map<String, dynamic>>.from(items);
      _lastAdminTicketsRefreshAt = DateTime.now();
      _adminTicketsControllerFor().add(List<Map<String, dynamic>>.from(items));
      return items;
    }();
    _adminTicketsInFlight = future;
    try {
      return await future;
    } catch (error) {
      if (error is ApiException && error.isUnauthorized) {
        _debugSource(
            'Support source: Timeweb admin unauthorized, resetting state');
        _resetAdminState();
        return const <Map<String, dynamic>>[];
      }
      rethrow;
    } finally {
      if (identical(_adminTicketsInFlight, future)) {
        _adminTicketsInFlight = null;
      }
    }
  }

  StreamController<List<Map<String, dynamic>>> _messageControllerFor(
    String ticketId,
  ) {
    return _messageControllers.putIfAbsent(
      ticketId,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  StreamController<List<Map<String, dynamic>>> _adminTicketsControllerFor() {
    return _adminTicketsController ??=
        StreamController<List<Map<String, dynamic>>>.broadcast();
  }

  void _ensureMessagePolling(String ticketId) {
    final normalizedTicketId = ticketId.trim();
    if (normalizedTicketId.isEmpty ||
        _missingTicketIds.contains(normalizedTicketId) ||
        _messagePollers.containsKey(normalizedTicketId) ||
        (_messageListenerCounts[normalizedTicketId] ?? 0) <= 0) {
      return;
    }
    final pollInterval = _ticketUsesAdminEndpoint[normalizedTicketId] == true
        ? _adminPollInterval
        : _messagePollInterval;
    _messagePollers[normalizedTicketId] = Timer.periodic(
      pollInterval,
      (_) async {
        try {
          await _refreshMessages(
            normalizedTicketId,
            useAdminEndpoint:
                _ticketUsesAdminEndpoint[normalizedTicketId] == true,
          );
        } catch (_) {}
      },
    );
  }

  void _stopMessagePolling(String ticketId) {
    _messagePollers.remove(ticketId)?.cancel();
  }

  Future<bool> _canUseAdminEndpoints() async {
    if (!_adminSessionActive) return false;
    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken == null || accessToken.trim().isEmpty) {
      return false;
    }
    final currentUser = await _tokenStorage.readCurrentUser();
    return currentUser?.isAdmin == true;
  }

  void _resetAdminState() {
    _adminTicketsPoller?.cancel();
    _adminTicketsPoller = null;
    _adminTicketsCache = const <Map<String, dynamic>>[];
    _adminTicketsInFlight = null;
    _lastAdminTicketsRefreshAt = null;
    _adminTicketsController?.add(const <Map<String, dynamic>>[]);
  }

  Future<void> _loadHiddenAdminTickets() async {
    final currentUser = await _tokenStorage.readCurrentUser();
    final uid = currentUser?.uid.trim() ?? '';
    if (_hiddenAdminTicketsOwnerUid == uid) {
      return;
    }
    _hiddenAdminTicketsOwnerUid = uid;
    _hiddenAdminTickets = <String, String>{};
    if (uid.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString('$_hiddenAdminTicketsPrefsKeyPrefix:$uid')?.trim();
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _hiddenAdminTickets = decoded.map(
          (key, value) => MapEntry(
            key.toString().trim(),
            value?.toString().trim() ?? '',
          ),
        )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
      }
    } catch (_) {
      _hiddenAdminTickets = <String, String>{};
    }
  }

  Future<void> _saveHiddenAdminTickets() async {
    final uid = _hiddenAdminTicketsOwnerUid?.trim() ?? '';
    if (uid.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_hiddenAdminTicketsPrefsKeyPrefix:$uid',
      jsonEncode(_hiddenAdminTickets),
    );
  }

  Future<List<Map<String, dynamic>>> _filterHiddenAdminTickets(
    List<Map<String, dynamic>> items,
  ) async {
    await _loadHiddenAdminTickets();
    if (_hiddenAdminTickets.isEmpty) {
      return items;
    }

    final visible = <Map<String, dynamic>>[];
    var mutated = false;
    for (final item in items) {
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        visible.add(item);
        continue;
      }
      final hiddenUpdatedAt = _hiddenAdminTickets[id]?.trim() ?? '';
      if (hiddenUpdatedAt.isEmpty) {
        visible.add(item);
        continue;
      }
      final itemUpdatedAt = (item['updated_at'] ?? '').toString().trim();
      final itemUpdatedAtDt = DateTime.tryParse(itemUpdatedAt);
      final hiddenUpdatedAtDt = DateTime.tryParse(hiddenUpdatedAt);
      final shouldStayHidden = itemUpdatedAtDt != null &&
          hiddenUpdatedAtDt != null &&
          !itemUpdatedAtDt.isAfter(hiddenUpdatedAtDt);
      if (shouldStayHidden) {
        continue;
      }
      _hiddenAdminTickets.remove(id);
      mutated = true;
      visible.add(item);
    }

    if (mutated) {
      await _saveHiddenAdminTickets();
    }

    return visible;
  }

  bool _isAdminTicketsRefreshStale() {
    final lastRefreshAt = _lastAdminTicketsRefreshAt;
    if (lastRefreshAt == null) return true;
    return DateTime.now().difference(lastRefreshAt) >= _adminTicketsCacheTtl;
  }

  @visibleForTesting
  int get activeMessagePollerCount => _messagePollers.length;

  void _publishMessages(String ticketId, List<Map<String, dynamic>> items) {
    final normalized = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _messageCache[ticketId] = normalized;
    _messageControllerFor(ticketId)
        .add(List<Map<String, dynamic>>.from(normalized));
  }

  void _markMessageFailed(
    String ticketId,
    String messageId, [
    String? errorText,
  ]) {
    final current = _messageCache[ticketId] ?? const <Map<String, dynamic>>[];
    _publishMessages(
      ticketId,
      current
          .map((item) => (item['id'] ?? '').toString() == messageId
              ? <String, dynamic>{
                  ...item,
                  'local_status': 'failed',
                  'error_text': (errorText ?? '').trim().isNotEmpty
                      ? errorText!.trim()
                      : kNetworkVpnHintMessage,
                }
              : item)
          .toList(),
    );
  }

  Map<String, dynamic> _buildOptimisticMessage({
    required String ticketId,
    required String text,
    required String sender,
    String imageUrl = '',
    String? localImagePath,
    String? messageId,
  }) {
    return <String, dynamic>{
      'id': (messageId ?? '').trim().isNotEmpty
          ? messageId!.trim()
          : 'local-${_uuid.v4()}',
      'ticket_id': ticketId,
      'sender': sender,
      'text': text,
      'image_url': imageUrl,
      if ((localImagePath ?? '').trim().isNotEmpty)
        'local_image_path': localImagePath,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'is_local_only': true,
      'local_status': 'pending',
    };
  }

  Map<String, dynamic> _normalizeMessageMap(Map<dynamic, dynamic> raw) {
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final normalizedText = _pickMessageText(map);
    final normalizedImageUrl = _pickImageUrl(map);
    return <String, dynamic>{
      ...map,
      'text': normalizedText,
      'body': normalizedText,
      'message': normalizedText,
      'content': normalizedText,
      'caption': normalizedText,
      'image_url': normalizedImageUrl,
      'created_at': _pickCreatedAt(map),
      'sender': (map['sender'] ?? '').toString().trim().toLowerCase(),
    };
  }

  String _pickMessageText(Map<String, dynamic> map) {
    final candidates = <dynamic>[
      map['text'],
      map['body'],
      map['message'],
      map['content'],
      map['caption'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _pickImageUrl(Map<String, dynamic> map) {
    final candidates = <dynamic>[
      map['image_url'],
      map['imageUrl'],
      map['photo_url'],
      map['photoUrl'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _pickCreatedAt(Map<String, dynamic> map) {
    final candidates = <dynamic>[
      map['created_at'],
      map['createdAt'],
      map['updated_at'],
      map['updatedAt'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  Future<String> _uploadImageIfNeeded(
    File? imageFile, {
    String? ticketId,
  }) async {
    if (imageFile == null) return '';
    final bytes = await imageFile.readAsBytes();
    final fileName = imageFile.uri.pathSegments.isEmpty
        ? 'support-image.jpg'
        : imageFile.uri.pathSegments.last;
    final response = await _api.uploadImage(
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      contentType: _guessContentType(fileName),
      ticketId: ticketId,
    );
    if (kDebugMode) {
      final rawUrl = (response['url'] ?? '').toString().trim();
      final resolution = resolveMediaUrl(
        rawUrl,
        categoryHint: 'support',
      );
      debugPrint(
        'Support upload response imageUrl=$rawUrl resolved=${resolution.resolvedUrl} category=support provider=${resolution.provider}',
      );
    }
    return (response['url'] ?? '').toString().trim();
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _messageErrorText(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 413 || error.code == 'payload_too_large') {
        return 'Файл слишком большой. Выберите другое фото.';
      }
      if (error.isTimeout || error.isNetworkError) {
        return kNetworkVpnHintMessage;
      }
      final message = error.message.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
    return kNetworkVpnHintMessage;
  }

  List<Map<String, dynamic>> _mergeMessages(
    List<Map<String, dynamic>> current,
    List<Map<String, dynamic>> incoming, {
    Set<String> removedIds = const <String>{},
  }) {
    final byId = <String, Map<String, dynamic>>{};
    final signatureToId = <String, String>{};

    void upsert(Map<String, dynamic> item) {
      final normalized = Map<String, dynamic>.from(item);
      final id = (normalized['id'] ?? '').toString();
      if (id.isEmpty || removedIds.contains(id)) return;

      final signature = _messageSignature(normalized);
      final existingIdForSignature = signatureToId[signature];
      if (existingIdForSignature != null && existingIdForSignature != id) {
        final existing = byId[existingIdForSignature];
        if (existing != null) {
          final merged = _preferSupportMessage(existing, normalized);
          final mergedId = (merged['id'] ?? '').toString();
          byId.remove(existingIdForSignature);
          if (mergedId.isNotEmpty && !removedIds.contains(mergedId)) {
            byId[mergedId] = merged;
            signatureToId[signature] = mergedId;
          }
          return;
        }
      }

      byId[id] = normalized;
      signatureToId[signature] = id;
    }

    for (final item in current) {
      upsert(item);
    }
    for (final item in incoming) {
      upsert(item);
    }

    final merged = byId.values.toList()
      ..sort((a, b) {
        final left = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final right = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
    return merged;
  }

  String _messageSignature(Map<String, dynamic> item) {
    final sender = (item['sender'] ?? '').toString().trim().toLowerCase();
    final text = _pickMessageText(item);
    final imageUrl = _pickImageUrl(item);
    final createdAt = DateTime.tryParse(_pickCreatedAt(item))?.toUtc();
    final normalizedCreatedAt = createdAt == null
        ? ''
        : DateTime.utc(
            createdAt.year,
            createdAt.month,
            createdAt.day,
            createdAt.hour,
            createdAt.minute,
            createdAt.second,
          ).toIso8601String();
    return [
      sender,
      text,
      imageUrl.startsWith('file://') ? '' : imageUrl,
      normalizedCreatedAt,
    ].join('|');
  }

  Map<String, dynamic> _preferSupportMessage(
    Map<String, dynamic> existing,
    Map<String, dynamic> candidate,
  ) {
    final existingLocalOnly = existing['is_local_only'] == true;
    final candidateLocalOnly = candidate['is_local_only'] == true;
    if (existingLocalOnly && !candidateLocalOnly) {
      return <String, dynamic>{...existing, ...candidate};
    }
    if (!existingLocalOnly && candidateLocalOnly) {
      return <String, dynamic>{...candidate, ...existing};
    }
    final existingFailed = (existing['local_status'] ?? '').toString() == 'failed';
    final candidateFailed =
        (candidate['local_status'] ?? '').toString() == 'failed';
    if (existingFailed && !candidateFailed) {
      return <String, dynamic>{...existing, ...candidate};
    }
    if (!existingFailed && candidateFailed) {
      return <String, dynamic>{...candidate, ...existing};
    }
    return <String, dynamic>{...existing, ...candidate};
  }
}
