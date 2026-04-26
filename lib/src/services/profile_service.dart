import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final SupabaseClient _db = Supabase.instance.client;
  final Map<String, Map<String, dynamic>> _profileCache = {};

  Map<String, dynamic> _normalizeRow(Map<String, dynamic>? row) {
    if (row == null || row.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(row);
  }

  Map<String, dynamic> _mergeRows(
    Map<String, dynamic>? base,
    Map<String, dynamic>? override,
  ) {
    final merged = <String, dynamic>{};
    if (base != null && base.isNotEmpty) merged.addAll(base);
    if (override != null && override.isNotEmpty) merged.addAll(override);
    return merged;
  }

  void _cacheProfile(String uid, Map<String, dynamic> row) {
    final id = uid.trim();
    if (id.isEmpty || row.isEmpty) return;
    _profileCache[id] = _normalizeRow(row);
  }

  Map<String, dynamic> getCachedProfile(String uid) {
    final id = uid.trim();
    if (id.isEmpty) return <String, dynamic>{};
    return _normalizeRow(_profileCache[id]);
  }

  void seedProfile(String uid, Map<String, dynamic> row) {
    _cacheProfile(uid, row);
  }

  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    final id = uid.trim();
    if (id.isEmpty) {
      yield <String, dynamic>{};
      return;
    }

    final seeded = _mergeRows(getCachedProfile(id), _normalizeRow(seed));
    if (seeded.isNotEmpty) {
      _cacheProfile(id, seeded);
      yield seeded;
    }

    await for (final rows
        in _db.from('users').stream(primaryKey: ['id']).eq('id', id)) {
      final live = rows.isNotEmpty
          ? Map<String, dynamic>.from(rows.first)
          : getCachedProfile(id);
      if (live.isNotEmpty) _cacheProfile(id, live);
      yield _mergeRows(seeded, live);
    }
  }

  Future<Map<String, dynamic>> getProfile(String uid) async {
    final row = await _db.from('users').select().eq('id', uid).maybeSingle();
    final normalized = _normalizeRow(row);
    if (normalized.isNotEmpty) _cacheProfile(uid, normalized);
    return normalized;
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    await _db.from('users').upsert({'id': uid, ...data}, onConflict: 'id');
    _cacheProfile(uid, _mergeRows(getCachedProfile(uid), {'id': uid, ...data}));
  }

  // Display name for the UI.
  String pickNameFromRow(
    Map<String, dynamic> row, {
    String fallback = 'Пользователь',
  }) {
    final dn =
        (row['display_name'] ?? row['displayName'] ?? '').toString().trim();
    final name = (row['name'] ?? '').toString().trim();
    final email = (row['email'] ?? '').toString().trim();
    return dn.isNotEmpty
        ? dn
        : (name.isNotEmpty ? name : (email.isNotEmpty ? email : fallback));
  }

  // Avatar URL from the users row.
  String pickAvatarFromRow(Map<String, dynamic> row) {
    final a1 = (row['avatar_url'] ?? '').toString().trim();
    if (a1.isNotEmpty) return a1;
    final a2 = (row['photo_url'] ?? '').toString().trim();
    if (a2.isNotEmpty) return a2;
    return '';
  }

  // ===============================
  // Universal avatar upload (Web + Android + iOS)
  // ===============================
  Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    const bucket = 'avatars'; // Public storage bucket.
    final ext = contentType.contains('png') ? 'png' : 'jpg';
    final path = '$uid/avatar.$ext';

    await _db.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: true,
            contentType: contentType,
          ),
        );

    // Public bucket returns a URL immediately.
    final url = _db.storage.from(bucket).getPublicUrl(path);

    // Mirror avatar fields in users so the UI stays consistent.
    await updateProfile(uid, {
      'avatar_url': url,
      'photo_url': url,
    });

    return url;
  }

  // ===== Profile stats streams =====

  Stream<int> streamMyListingsCount(String uid) {
    final stream = _db.from('listings').stream(primaryKey: ['id']);
    return stream.map(
      (rows) => rows
          .where(
            (r) =>
                r['owner_id']?.toString() == uid &&
                (r['status'] ?? '').toString() == 'approved',
          )
          .length,
    );
  }

  Stream<double> streamMyRatingAvg(String uid) {
    final stream = _db.from('reviews').stream(primaryKey: ['id']);
    return stream.map((rows) {
      final my = rows.where((r) => r['seller_id']?.toString() == uid).toList();
      if (my.isEmpty) return 0.0;
      final sum = my.fold<num>(0, (p, r) => p + ((r['rating'] as num?) ?? 0));
      return (sum / my.length).toDouble();
    });
  }

  Stream<int> streamMyReviewsCount(String uid) {
    final stream = _db.from('reviews').stream(primaryKey: ['id']);
    return stream.map(
        (rows) => rows.where((r) => r['seller_id']?.toString() == uid).length);
  }

  Stream<String> streamDisplayName(
    String uid, {
    String fallback = 'Пользователь',
  }) {
    return streamProfile(uid)
        .map((row) => pickNameFromRow(row, fallback: fallback));
  }

  Future<String> getDisplayName(
    String uid, {
    String fallback = 'Пользователь',
  }) async {
    final row = await getProfile(uid);
    return pickNameFromRow(row, fallback: fallback);
  }
}
