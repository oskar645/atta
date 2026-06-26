import 'package:atta/src/services/api/api_config.dart';
import 'package:flutter/foundation.dart';

class MediaUrlResolution {
  const MediaUrlResolution({
    required this.originalUrl,
    required this.resolvedUrl,
    required this.provider,
    required this.category,
  });

  final String originalUrl;
  final String resolvedUrl;
  final String provider;
  final String category;

  bool get isProtectedChatMedia {
    final uri = Uri.tryParse(resolvedUrl);
    final path = uri?.path ?? resolvedUrl;
    return path.startsWith('/media/chats/');
  }
}

String resolvePublicMediaUrl(
  String rawUrl, {
  String? categoryHint,
}) {
  return resolveMediaUrl(
    rawUrl,
    categoryHint: categoryHint,
  ).resolvedUrl;
}

MediaUrlResolution resolveMediaUrl(
  String rawUrl, {
  String? categoryHint,
}) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty || trimmed.startsWith('file://')) {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: trimmed.startsWith('file://') ? 'local-file' : 'empty',
      category: categoryHint?.trim().isNotEmpty == true
          ? categoryHint!.trim()
          : 'unknown',
    );
  }

  if (trimmed.startsWith('/media/') || trimmed.startsWith('/uploads/')) {
    final resolved = '${ApiConfig.baseUrl}$trimmed';
    _debugMediaFlow(
      originalUrl: trimmed,
      resolvedUrl: resolved,
      provider: trimmed.startsWith('/uploads/') ? 'local' : 'proxy',
      category: categoryHint,
    );
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: resolved,
      provider: trimmed.startsWith('/uploads/') ? 'local' : 'proxy',
      category: _resolvedCategory(trimmed, categoryHint),
    );
  }

  if (trimmed.startsWith('uploads/')) {
    final resolved = '${ApiConfig.baseUrl}/$trimmed';
    _debugMediaFlow(
      originalUrl: trimmed,
      resolvedUrl: resolved,
      provider: 'local',
      category: categoryHint,
    );
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: resolved,
      provider: 'local',
      category: _resolvedCategory(trimmed, categoryHint),
    );
  }

  if (!trimmed.contains('://') && trimmed.contains('/')) {
    final key = _normalizeS3Key(trimmed);
    final category = _resolveCategory(key, categoryHint: categoryHint);
    if (category != null) {
      final resolved = _buildProxyUrl(category, key);
      _debugMediaFlow(
        originalUrl: trimmed,
        resolvedUrl: resolved,
        provider: category == 'chats' ? 'proxy-chat' : 'proxy',
        category: category,
      );
      return MediaUrlResolution(
        originalUrl: trimmed,
        resolvedUrl: resolved,
        provider: 'proxy',
        category: category,
      );
    }
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 'unknown',
      category: _resolvedCategory(trimmed, categoryHint),
    );
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 'unknown',
      category: _resolvedCategory(trimmed, categoryHint),
    );
  }

  final baseUri = Uri.parse(ApiConfig.baseUrl);
  if (parsed.host == baseUri.host) {
    _debugMediaFlow(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: parsed.path.startsWith('/uploads/') ? 'local' : 'proxy',
      category: categoryHint,
    );
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: parsed.path.startsWith('/uploads/') ? 'local' : 'proxy',
      category: _resolvedCategory(parsed.path, categoryHint),
    );
  }

  if (parsed.host != 's3.twcstorage.ru') {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 'remote',
      category: _resolvedCategory(parsed.path, categoryHint),
    );
  }

  final segments = parsed.pathSegments
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.length < 2) {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 'remote',
      category: _resolvedCategory(parsed.path, categoryHint),
    );
  }

  while (segments.length >= 2 && segments[0] == segments[1]) {
    segments.removeAt(0);
  }
  if (segments.length < 2) {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 'remote',
      category: _resolvedCategory(parsed.path, categoryHint),
    );
  }

  final key = _normalizeS3Key(segments.sublist(1).join('/'));
  final category = _resolveCategory(key, categoryHint: categoryHint);
  if (category == null) {
    return MediaUrlResolution(
      originalUrl: trimmed,
      resolvedUrl: trimmed,
      provider: 's3',
      category: _resolvedCategory(key, categoryHint),
    );
  }

  final resolved = _buildProxyUrl(category, key);
  _debugMediaFlow(
    originalUrl: trimmed,
    resolvedUrl: resolved,
    provider: category == 'chats' ? 'proxy-chat' : 'proxy',
    category: category,
  );
  return MediaUrlResolution(
    originalUrl: trimmed,
    resolvedUrl: resolved,
    provider: 's3',
    category: category,
  );
}

String _buildProxyUrl(String category, String key) {
  if (category == 'chats') {
    return ApiConfig.uri('/media/chats/file', <String, dynamic>{
      'key': key,
    }).toString();
  }
  return ApiConfig.uri('/media/object', <String, dynamic>{
    'category': category,
    'key': key,
  }).toString();
}

String _normalizeS3Key(String value) {
  var normalized =
      Uri.decodeFull(value.trim()).replaceFirst(RegExp(r'^/+'), '');
  final parts = normalized
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();
  while (parts.length >= 2 && parts[0] == parts[1]) {
    parts.removeAt(0);
  }
  return parts.join('/');
}

String? _resolveCategory(
  String key, {
  String? categoryHint,
}) {
  final normalizedHint = categoryHint?.trim();
  if (normalizedHint != null && normalizedHint.isNotEmpty) {
    return normalizedHint;
  }

  final lower = key.toLowerCase();
  if (lower.startsWith('avatars/')) return 'avatars';
  if (lower.startsWith('listings/') || lower.startsWith('listing-photos/')) {
    return 'listings';
  }
  if (lower.startsWith('chats/') || lower.startsWith('chat-images/')) {
    return 'chats';
  }
  if (lower.startsWith('support/') || lower.startsWith('support-images/')) {
    return 'support';
  }
  if (lower.startsWith('reports/')) return 'reports';
  if (lower.startsWith('videos/')) return 'videos';
  if (lower.startsWith('misc/')) return 'misc';
  if (lower.startsWith('feed-ads/')) return 'feed-ads';
  return null;
}

String _resolvedCategory(String value, String? categoryHint) {
  return _resolveCategory(value, categoryHint: categoryHint) ??
      (categoryHint?.trim().isNotEmpty == true ? categoryHint!.trim() : 'unknown');
}

void _debugMediaFlow({
  required String originalUrl,
  required String resolvedUrl,
  required String provider,
  String? category,
}) {
  if (!kDebugMode) return;
  debugPrint(
    'Media resolve category=${category ?? 'unknown'} provider=$provider original=$originalUrl resolved=$resolvedUrl',
  );
}
