import 'dart:async';
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

  test('seeded fresh avatar is not overwritten by older backend avatar',
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

  test('updateProfile returns fresh backend profile and updates cached user',
      () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'Old Name',
        phone: '+79281234567',
        phoneVerified: true,
        photoUrl: 'https://cdn.example.com/avatar.jpg',
        isAdmin: true,
      ),
    );
    final service = ProfileService(
      tokenStorage: tokenStorage,
      usersApi: _UpdateNameUsersApi(),
    );

    final updated = await service.updateProfile(
      'user-1',
      <String, dynamic>{
        'display_name': 'New Name',
        'name': 'New Name',
      },
    );

    expect(updated['display_name'], 'New Name');
    expect(service.getCachedProfile('user-1')['display_name'], 'New Name');

    final savedUser = await tokenStorage.readCurrentUser();
    expect(savedUser?.displayName, 'New Name');
    expect(savedUser?.uid, 'user-1');
    expect(savedUser?.email, 'user@example.com');
    expect(savedUser?.phone, '+79281234567');
    expect(savedUser?.phoneVerified, isTrue);
    expect(savedUser?.photoUrl, 'https://cdn.example.com/avatar.jpg');
    expect(savedUser?.isAdmin, isTrue);
  });

  test('updateProfile error leaves cached current user unchanged', () async {
    final tokenStorage = TokenStorage();
    await tokenStorage.saveSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      currentUser: const AuthUser(
        uid: 'user-1',
        displayName: 'Old Name',
        phone: '+79281234567',
        phoneVerified: true,
      ),
    );
    final service = ProfileService(
      tokenStorage: tokenStorage,
      usersApi: _FailingUpdateUsersApi(),
    );

    await expectLater(
      service.updateProfile(
        'user-1',
        <String, dynamic>{
          'display_name': 'New Name',
          'name': 'New Name',
        },
      ),
      throwsException,
    );

    final savedUser = await tokenStorage.readCurrentUser();
    expect(savedUser?.displayName, 'Old Name');
    expect(savedUser?.phone, '+79281234567');
    expect(savedUser?.phoneVerified, isTrue);
  });
  test('late ProfileService me A cannot persist A with tokens B', () async {
    final storage = TokenStorage();
    await storage.saveSession(
        accessToken: 'a',
        refreshToken: 'a',
        currentUser: const AuthUser(uid: 'a'));
    final users = _DelayedProfileUsersApi();
    final service = ProfileService(tokenStorage: storage, usersApi: users);
    final profile = service.getProfile('a');
    await users.started.future;
    storage.beginSessionChange();
    await storage.saveSession(
        accessToken: 'b',
        refreshToken: 'b',
        currentUser: const AuthUser(uid: 'b'));
    users.pending.complete({
      'user': {'id': 'a', 'display_name': 'old'}
    });
    await profile;
    expect((await storage.readCurrentUser())?.uid, 'b');
    expect(await storage.readAccessToken(), 'b');
    expect(await storage.readRefreshToken(), 'b');
  });

  test('seed without sellerLevel is followed by fresh backend bronze',
      () async {
    final users = _SellerLevelUsersApi(<Map<String, dynamic>>[
      {
        'user': {'id': 'seller-1', 'sellerLevel': 'bronze'}
      },
    ]);
    final service = ProfileService(usersApi: users);

    final rows = await service.streamProfile(
      'seller-1',
      seed: {'id': 'seller-1', 'display_name': 'Seller'},
    ).toList();

    expect(rows.first['sellerLevel'], isNull);
    expect(rows.last['sellerLevel'], 'bronze');
    expect(users.calls, 1);
  });

  test('force refresh replaces stale cached bronze with backend null',
      () async {
    final users = _SellerLevelUsersApi(<Map<String, dynamic>>[
      {
        'user': {'id': 'seller-1', 'sellerLevel': null}
      },
    ]);
    final service = ProfileService(usersApi: users);
    service
        .seedProfile('seller-1', {'id': 'seller-1', 'sellerLevel': 'bronze'});

    final refreshed = await service.getProfile('seller-1', forceRefresh: true);

    expect(refreshed.containsKey('sellerLevel'), isTrue);
    expect(refreshed['sellerLevel'], isNull);
  });

  test('force refresh replaces stale null with backend silver', () async {
    final users = _SellerLevelUsersApi(<Map<String, dynamic>>[
      {
        'user': {'id': 'seller-1', 'seller_level': 'silver'}
      },
    ]);
    final service = ProfileService(usersApi: users);
    service.seedProfile('seller-1', {'id': 'seller-1', 'sellerLevel': null});

    final refreshed = await service.getProfile('seller-1', forceRefresh: true);

    expect(refreshed['seller_level'], 'silver');
  });

  test('force refresh bypasses fresh profile TTL', () async {
    final users = _SellerLevelUsersApi(<Map<String, dynamic>>[
      {
        'user': {'id': 'seller-1', 'sellerLevel': 'bronze'}
      },
      {
        'user': {'id': 'seller-1', 'sellerLevel': 'gold'}
      },
    ]);
    final service = ProfileService(usersApi: users);

    expect((await service.getProfile('seller-1'))['sellerLevel'], 'bronze');
    expect((await service.getProfile('seller-1'))['sellerLevel'], 'bronze');
    expect(users.calls, 1);
    expect(
      (await service.getProfile('seller-1', forceRefresh: true))['sellerLevel'],
      'gold',
    );
    expect(users.calls, 2);
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

class _UpdateNameUsersApi extends UsersApi {
  _UpdateNameUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  @override
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async {
    return <String, dynamic>{
      'user': <String, dynamic>{
        'id': 'user-1',
        'display_name': data['display_name'],
        'name': data['name'],
      },
    };
  }
}

class _FailingUpdateUsersApi extends UsersApi {
  _FailingUpdateUsersApi()
      : super(
          ApiClient(
            tokenStorage: TokenStorage(),
          ),
        );

  @override
  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async {
    throw Exception('patch failed');
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

class _DelayedProfileUsersApi extends _FakeUsersApi {
  final started = Completer<void>();
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> me() {
    started.complete();
    return pending.future;
  }
}

class _SellerLevelUsersApi extends UsersApi {
  _SellerLevelUsersApi(this.responses)
      : super(ApiClient(tokenStorage: TokenStorage()));

  final List<Map<String, dynamic>> responses;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> publicProfile(String userId) async {
    final response =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls += 1;
    return response;
  }
}
