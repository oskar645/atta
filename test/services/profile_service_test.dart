import 'dart:convert';
import 'dart:typed_data';

import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/media_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/image_preparation_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('pickAvatarFromRow prefers avatar_url and falls back to photo_url', () {
    final service = ProfileService();

    expect(
      service.pickAvatarFromRow(<String, dynamic>{
        'avatar_url': 'https://cdn.example.com/avatar.jpg',
        'photo_url': 'https://cdn.example.com/photo.jpg',
        'updated_at': '2026-06-20T10:00:00.000Z',
      }),
      'https://cdn.example.com/avatar.jpg?v=2026-06-20T10%3A00%3A00.000Z',
    );

    expect(
      service.pickAvatarFromRow(<String, dynamic>{
        'photo_url': 'https://cdn.example.com/photo.jpg',
        'updated_at': '2026-06-20T10:00:00.000Z',
      }),
      'https://cdn.example.com/photo.jpg?v=2026-06-20T10%3A00%3A00.000Z',
    );

    expect(
      service.pickAvatarFromRow(<String, dynamic>{}),
      '',
    );
  });

  test('pickAvatarFromRow does not append duplicate cache buster', () {
    final service = ProfileService();

    expect(
      service.pickAvatarFromRow(<String, dynamic>{
        'avatar_url': 'https://cdn.example.com/avatar.jpg?v=old',
        'updated_at': '2026-06-20T10:00:00.000Z',
      }),
      'https://cdn.example.com/avatar.jpg?v=old',
    );
  });

  test('uploadAvatar updates cache, current user and evicts old image cache',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'ATTA User',
        photoUrl:
            'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      ),
    );

    final evicted = <String>[];
    final service = ProfileService(
      tokenStorage: tokenStorage,
      mediaApi: _FakeMediaApi(),
      usersApi: _FakeUsersApi(),
      imagePreparationService: _FakeImagePreparationService(),
      avatarCacheEvictor: (url) async {
        evicted.add(url);
      },
    );
    service.seedProfile('user-1', <String, dynamic>{
      'id': 'user-1',
      'display_name': 'ATTA User',
      'avatar_url':
          'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      'photo_url':
          'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      'updated_at': '2026-06-20T10:00:00.000Z',
    });

    final result = await service.uploadAvatar(
      uid: 'user-1',
      bytes: _tinyPngBytes,
      fileName: 'avatar.png',
      contentType: 'image/png',
    );

    expect(result.previousAvatarUrl, contains('old.jpg'));
    expect(
        result.avatarUrl, contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'));
    expect(
      service.getCachedProfile('user-1')['avatar_url'],
      contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );
    expect(evicted, hasLength(2));
    expect(evicted.first, contains('old.jpg'));
    expect(evicted.last, contains('new.jpg'));

    final savedUser = await tokenStorage.readCurrentUser();
    expect(
      savedUser?.photoUrl,
      contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );
  });

  test('seeded fresh avatar is not overwritten by older backend avatar', () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'ATTA User',
        photoUrl:
            'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
      ),
    );

    final service = ProfileService(
      tokenStorage: tokenStorage,
      usersApi: _StaleAvatarUsersApi(),
    );
    service.seedProfile('user-1', <String, dynamic>{
      'id': 'user-1',
      'display_name': 'ATTA User',
      'avatar_url':
          'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
      'photo_url':
          'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
      'updated_at': '2026-06-25T10:00:00.000Z',
      'avatar_updated_at': '2026-06-25T10:00:00.000Z',
    });

    final profile = await service.getProfile('user-1');

    expect(
      profile['avatar_url'],
      contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );
    final savedUser = await tokenStorage.readCurrentUser();
    expect(
      savedUser?.photoUrl,
      contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );
  });
}

class _FakeMediaApi extends MediaApi {
  _FakeMediaApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  @override
  Future<Map<String, dynamic>> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
        'display_name': 'ATTA User',
        'avatar_url': 'https://cdn.example.com/new.jpg',
        'photo_url': 'https://cdn.example.com/new.jpg',
        'updated_at': '2026-06-25T10:00:00.000Z',
        'avatar_updated_at': '2026-06-25T10:00:00.000Z',
      },
      'avatar_url': 'https://cdn.example.com/new.jpg',
      'photo_url': 'https://cdn.example.com/new.jpg',
    };
  }
}

class _FakeUsersApi extends UsersApi {
  _FakeUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );
}

class _StaleAvatarUsersApi extends UsersApi {
  _StaleAvatarUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  @override
  Future<Map<String, dynamic>> me() async {
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
        'display_name': 'ATTA User',
        'avatar_url': 'https://cdn.example.com/old.jpg',
        'photo_url': 'https://cdn.example.com/old.jpg',
        'updated_at': '2026-06-20T10:00:00.000Z',
        'avatar_updated_at': '2026-06-20T10:00:00.000Z',
      },
    };
  }
}

class _FakeImagePreparationService extends ImagePreparationService {
  @override
  Future<PreparedImage> prepareAvatarBytes(
    Uint8List bytes, {
    String fileName = 'avatar.jpg',
  }) async {
    return PreparedImage(
      bytes: bytes,
      fileName: fileName,
      contentType: 'image/png',
      originalBytes: bytes.length,
      compressedBytes: bytes.length,
    );
  }
}

final Uint8List _tinyPngBytes = base64Decode('AQID');
