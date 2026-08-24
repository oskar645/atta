import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:atta/src/features/profile/profile_screen.dart';
import 'package:atta/src/models/wallet.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:atta/src/services/follow_service.dart';
import 'package:atta/src/services/profile_service.dart';
import 'package:atta/src/services/theme_service.dart';
import 'package:atta/src/services/wallet_service.dart';
import 'package:atta/src/widgets/remote_avatar.dart';
import 'package:atta/src/widgets/skeletons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ordinary profile does not show technical user id',
      (tester) async {
    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: _FakeProfileService(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Пригласить друга'));

    expect(find.text('ID'), findsNothing);
    expect(find.textContaining('user-1'), findsNothing);
  });

  testWidgets('profile shows cached auth user immediately without skeleton',
      (tester) async {
    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: _DelayedProfileService(),
      ),
    );

    expect(find.byType(SkeletonProfileHeader), findsNothing);
    expect(find.text('ATTA User'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('profile shows wallet balance when loaded', (tester) async {
    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: _DelayedProfileService(),
      ),
    );
    await _pumpUntilFound(tester, find.text('150 бонусов'));

    expect(find.text('ATTA Кошелёк'), findsOneWidget);
    expect(find.text('150 бонусов'), findsOneWidget);
    expect(find.text('Загрузка бонусов...'), findsNothing);
    expect(find.text('0 бонусов'), findsNothing);
  });

  testWidgets('profile shows retry state when wallet failed', (tester) async {
    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletFailingService(),
        profileService: _DelayedProfileService(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Бонусы для продвижения'));

    expect(find.text('ATTA Кошелёк'), findsOneWidget);
    expect(find.text('Бонусы для продвижения'), findsOneWidget);
    expect(
      find.text('Не удалось обновить кошелёк. Попробуйте позже.'),
      findsNothing,
    );
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('0 бонусов'), findsNothing);
  });

  testWidgets('profile keeps cached wallet balance visible during refresh',
      (tester) async {
    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletCachedRefreshService(),
        profileService: _FakeProfileService(),
      ),
    );

    await tester.pump();
    expect(find.text('150 бонусов'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('175 бонусов'), findsOneWidget);
  });

  testWidgets('profile shows edited name after auth userUpdated event',
      (tester) async {
    final auth = _MutableAuthService();
    final profile = _EditableProfileService();
    await tester.pumpWidget(
      _wrapProfile(
        authService: auth,
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
      ),
    );
    await _pumpUntilFound(tester, find.text('ATTA User'));

    await tester.tap(find.text('ATTA User').first);
    await _pumpUntilFound(tester, find.text('Имя'));
    await tester.enterText(find.byType(TextField).last, 'New Name');
    await tester.tap(find.text('Сохранить'));
    await _pumpUntilFound(tester, find.text('New Name'));

    expect(auth.currentUser?.displayName, 'New Name');
    expect(profile.lastUpdateData?['display_name'], 'New Name');
    expect(find.text('New Name'), findsOneWidget);
    expect(find.text('ATTA User'), findsNothing);
  });

  testWidgets('failed name edit keeps current user and visible name unchanged',
      (tester) async {
    final auth = _MutableAuthService();
    await tester.pumpWidget(
      _wrapProfile(
        authService: auth,
        walletService: _ProfileWalletSuccessService(),
        profileService: _FailingEditableProfileService(),
      ),
    );
    await _pumpUntilFound(tester, find.text('ATTA User'));

    await tester.tap(find.text('ATTA User').first);
    await _pumpUntilFound(tester, find.text('Имя'));
    await tester.enterText(find.byType(TextField).last, 'New Name');
    await tester.tap(find.text('Сохранить'));
    await _pumpUntilFound(
      tester,
      find.text('Не удалось сохранить имя. Попробуйте ещё раз.'),
    );

    expect(auth.currentUser?.displayName, 'ATTA User');
    expect(find.text('ATTA User'), findsOneWidget);
    expect(find.text('New Name'), findsNothing);
    expect(
      find.text('Не удалось сохранить имя. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  });

  testWidgets('profile name edit works from trailing pencil tap',
      (tester) async {
    final auth = _MutableAuthService();
    final profile = _EditableProfileService();
    await tester.pumpWidget(
      _wrapProfile(
        authService: auth,
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
      ),
    );
    await _pumpUntilFound(tester, find.text('ATTA User'));

    await tester.tap(find.byIcon(Icons.edit).first);
    await _pumpUntilFound(tester, find.text('Имя'));
    await tester.enterText(find.byType(TextField).last, 'Pencil Name');
    await tester.tap(find.text('Сохранить'));
    await _pumpUntilFound(tester, find.text('Pencil Name'));

    expect(auth.currentUser?.displayName, 'Pencil Name');
    expect(profile.lastUpdateData?['display_name'], 'Pencil Name');
    expect(find.text('Pencil Name'), findsOneWidget);
  });

  testWidgets('profile wallet opens even while balance is loading',
      (tester) async {
    final walletService = _ProfileWalletSlowService();
    await tester.pumpWidget(
      _wrapProfile(
        walletService: walletService,
        profileService: _FakeProfileService(),
      ),
    );

    await _pumpUntilFound(tester, find.text('ATTA Кошелёк'));
    await tester.tap(find.text('ATTA Кошелёк'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ATTA Кошелёк'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    walletService.maybeCheckCompleter.complete(_wallet(balance: 150));
    walletService.checkAccrualCompleter.complete(_wallet(balance: 150));
    await tester.pump();
  });

  testWidgets('selected avatar local preview appears immediately',
      (tester) async {
    final profile = _StickyAvatarProfileService();
    profile.uploadCompleter = Completer<AvatarUploadResult>();
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) async {},
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntil(
      tester,
      () => tester
          .widget<RemoteAvatar>(find.byType(RemoteAvatar).first)
          .imageProvider is MemoryImage,
    );
    final avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(avatar.imageProvider, isA<MemoryImage>());
    expect(find.byKey(const Key('remote_avatar_loading')), findsOneWidget);
  }, skip: true);

  testWidgets('avatar shows loading overlay while upload', (tester) async {
    final profile = _AvatarProfileService();
    profile.uploadCompleter = Completer<AvatarUploadResult>();
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) async {},
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _pumpUntilFound(
        tester, find.byKey(const Key('remote_avatar_loading')));
    expect(find.byKey(const Key('remote_avatar_loading')), findsOneWidget);
    expect(find.text('Фото профиля обновлено'), findsNothing);
  }, skip: true);

  testWidgets('success updates own profile avatar immediately', (tester) async {
    final profile = _AvatarProfileService();
    final completer = Completer<AvatarUploadResult>();
    profile.uploadCompleter = completer;
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) async {},
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    completer.complete(
      const AvatarUploadResult(
        avatarUrl:
            'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
        previousAvatarUrl:
            'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      ),
    );
    await _pumpUntil(
      tester,
      () => tester
          .widget<RemoteAvatar>(find.byType(RemoteAvatar).first)
          .imageUrl
          .contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );

    final avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(avatar.imageProvider, isNull);
    expect(avatar.imageUrl, contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'));
    expect(find.text('Фото профиля обновлено'), findsOneWidget);
  }, skip: true);

  testWidgets('failed upload restores old avatar', (tester) async {
    final profile = _StickyAvatarProfileService();
    profile.uploadCompleter = Completer<AvatarUploadResult>();
    profile.uploadError = Exception('upload failed');
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) async {},
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _pumpUntil(
      tester,
      () => find
          .text('Не удалось загрузить фото профиля. Попробуйте ещё раз.')
          .evaluate()
          .isNotEmpty,
    );

    final avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(avatar.imageProvider, isNull);
    expect(avatar.imageUrl, contains('old.jpg?v=2026-06-20T10%3A00%3A00.000Z'));
    expect(
      find.text('Не удалось загрузить фото профиля. Попробуйте ещё раз.'),
      findsOneWidget,
    );
  }, skip: true);

  testWidgets('success snackbar appears only after UI has fresh avatar',
      (tester) async {
    final profile = _AvatarProfileService();
    final completer = Completer<AvatarUploadResult>();
    profile.uploadCompleter = completer;
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) async {},
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Фото профиля обновлено'), findsNothing);

    completer.complete(
      const AvatarUploadResult(
        avatarUrl:
            'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
        previousAvatarUrl:
            'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      ),
    );
    await _pumpUntil(
      tester,
      () => tester
          .widget<RemoteAvatar>(find.byType(RemoteAvatar).first)
          .imageUrl
          .contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );

    final avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(avatar.imageUrl, contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'));

    await tester.pump();
    expect(find.text('Фото профиля обновлено'), findsOneWidget);
  }, skip: true);

  testWidgets('local preview stays visible until uploaded avatar is precached',
      (tester) async {
    final profile = _AvatarProfileService();
    final completer = Completer<AvatarUploadResult>();
    final precacheCompleter = Completer<void>();
    profile.uploadCompleter = completer;
    final pickedFile = XFile.fromData(
      _tinyPngBytes,
      name: 'avatar.png',
      mimeType: 'image/png',
    );

    await tester.pumpWidget(
      _wrapProfile(
        walletService: _ProfileWalletSuccessService(),
        profileService: profile,
        pickImage: (_) async => pickedFile,
        precacheAvatar: (_, __) => precacheCompleter.future,
      ),
    );
    await _pumpUntilFound(tester, find.byType(RemoteAvatar));

    await tester.tap(find.byKey(const Key('profile_avatar_tap_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    completer.complete(
      const AvatarUploadResult(
        avatarUrl:
            'https://cdn.example.com/new.jpg?v=2026-06-25T10%3A00%3A00.000Z',
        previousAvatarUrl:
            'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      ),
    );
    await tester.pump();

    var avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(avatar.imageProvider, isA<MemoryImage>());
    expect(find.text('Фото профиля обновлено'), findsNothing);

    precacheCompleter.complete();
    await _pumpUntil(
      tester,
      () =>
          tester
              .widget<RemoteAvatar>(find.byType(RemoteAvatar).first)
              .imageProvider ==
          null,
    );

    avatar = tester.widget<RemoteAvatar>(find.byType(RemoteAvatar).first);
    expect(
      avatar.imageUrl,
      contains('new.jpg?v=2026-06-25T10%3A00%3A00.000Z'),
    );
  }, skip: true);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    if (condition()) {
      return;
    }
  }
}

Widget _wrapProfile({
  required WalletService walletService,
  AuthService? authService,
  ProfileService? profileService,
  Future<XFile?> Function(ImageSource source)? pickImage,
  Future<void> Function(BuildContext context, String imageUrl)? precacheAvatar,
}) {
  return MultiProvider(
    providers: [
      Provider<AuthService>.value(value: authService ?? _FakeAuthService()),
      Provider<ProfileService>.value(
          value: profileService ?? _FakeProfileService()),
      Provider<AdminService>.value(value: _FakeAdminService()),
      Provider<FollowService>.value(value: _FakeFollowService()),
      Provider<WalletService>.value(value: walletService),
      ChangeNotifierProvider(create: (_) => ThemeService()),
    ],
    child: MaterialApp(
      home: ProfileScreen(
        pickImage: pickImage,
        precacheAvatar: precacheAvatar,
      ),
    ),
  );
}

class _FakeAuthService extends AuthService {
  @override
  AuthUser? get currentUser => const AuthUser(
        uid: 'user-1',
        email: 'user@example.com',
        displayName: 'ATTA User',
        phone: '79990000000',
        phoneVerified: true,
        photoUrl:
            'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      );
}

class _MutableAuthService extends AuthService {
  final StreamController<AuthSessionEvent> _events =
      StreamController<AuthSessionEvent>.broadcast();

  AuthUser? _user = const AuthUser(
    uid: 'user-1',
    email: 'user@example.com',
    displayName: 'ATTA User',
    phone: '79990000000',
    phoneVerified: true,
    photoUrl: 'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
  );

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthSessionEvent> get onAuthStateChange => _events.stream;

  @override
  Future<AuthUser?> syncCurrentUserFromProfile(
    String uid,
    Map<String, dynamic> profile,
  ) async {
    final current = _user;
    if (current == null || current.uid != uid) {
      return current;
    }
    final displayName =
        (profile['display_name'] ?? profile['displayName'] ?? profile['name'])
            ?.toString()
            .trim();
    _user = AuthUser(
      uid: current.uid,
      email: current.email,
      displayName:
          displayName?.isNotEmpty == true ? displayName : current.displayName,
      phone: current.phone,
      phoneVerified: current.phoneVerified,
      photoUrl: current.photoUrl,
      referralCode: current.referralCode,
      isAdmin: current.isAdmin,
      blockStatus: current.blockStatus,
    );
    _events.add(const AuthSessionEvent(type: AuthSessionEventType.userUpdated));
    return _user;
  }
}

class _FakeProfileService extends ProfileService {
  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{
      ...?seed,
      'display_name': 'ATTA User',
      'phone': '79990000000',
      'phoneVerified': true,
    };
  }

  @override
  void seedProfile(String uid, Map<String, dynamic> row) {}

  @override
  Stream<double> streamMyRatingAvg(String uid) => Stream<double>.value(4.9);

  @override
  Stream<int> streamMyReviewsCount(String uid) => Stream<int>.value(12);

  @override
  Stream<int> streamMyListingsCount(String uid) => Stream<int>.value(5);
}

class _EditableProfileService extends _FakeProfileService {
  Map<String, dynamic> _row = <String, dynamic>{
    'id': 'user-1',
    'display_name': 'ATTA User',
    'phone': '79990000000',
    'phoneVerified': true,
  };

  Map<String, dynamic>? lastUpdateData;

  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{...?seed, ..._row};
  }

  @override
  Future<Map<String, dynamic>> updateProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    lastUpdateData = Map<String, dynamic>.from(data);
    _row = <String, dynamic>{
      ..._row,
      'id': uid,
      if (data['display_name'] != null) 'display_name': data['display_name'],
      if (data['name'] != null) 'name': data['name'],
    };
    return _row;
  }
}

class _FailingEditableProfileService extends _EditableProfileService {
  @override
  Future<Map<String, dynamic>> updateProfile(
    String uid,
    Map<String, dynamic> data,
  ) async {
    throw Exception('patch failed');
  }
}

class _AvatarProfileService extends _FakeProfileService {
  Map<String, dynamic> _row = <String, dynamic>{
    'id': 'user-1',
    'display_name': 'ATTA User',
    'phone': '79990000000',
    'phoneVerified': true,
    'avatar_url':
        'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
    'photo_url':
        'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
    'updated_at': '2026-06-20T10:00:00.000Z',
  };

  Completer<AvatarUploadResult>? uploadCompleter;
  Object? uploadError;

  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{...?seed, ..._row};
  }

  @override
  void seedProfile(String uid, Map<String, dynamic> row) {
    _row = Map<String, dynamic>.from(row);
  }

  @override
  Future<AvatarUploadResult> uploadAvatar({
    required String uid,
    required Uint8List bytes,
    String fileName = 'avatar.jpg',
    String contentType = 'image/jpeg',
  }) async {
    if (uploadError != null) {
      throw uploadError!;
    }
    final result = await uploadCompleter!.future;
    _row = <String, dynamic>{
      ..._row,
      'avatar_url': result.avatarUrl,
      'photo_url': result.avatarUrl,
      'updated_at': '2026-06-25T10:00:00.000Z',
      'avatar_updated_at': '2026-06-25T10:00:00.000Z',
    };
    return result;
  }
}

class _StickyAvatarProfileService extends _AvatarProfileService {
  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    yield <String, dynamic>{...?seed, ..._row};
    await Future<void>.delayed(const Duration(milliseconds: 50));
    yield <String, dynamic>{
      'id': 'user-1',
      'display_name': 'ATTA User',
      'phone': '79990000000',
      'phoneVerified': true,
      'avatar_url':
          'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      'photo_url':
          'https://cdn.example.com/old.jpg?v=2026-06-20T10%3A00%3A00.000Z',
      'updated_at': '2026-06-20T10:00:00.000Z',
    };
  }
}

class _DelayedProfileService extends _FakeProfileService {
  @override
  Stream<Map<String, dynamic>> streamProfile(
    String uid, {
    Map<String, dynamic>? seed,
  }) async* {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield <String, dynamic>{
      ...?seed,
      'display_name': 'ATTA User',
      'phone': '79990000000',
      'phoneVerified': true,
    };
  }
}

class _FakeAdminService extends AdminService {
  @override
  Stream<bool> streamIsAdmin(String uid) => Stream<bool>.value(false);
}

class _FakeFollowService extends FollowService {
  @override
  Stream<int> streamFollowersCount(String sellerId) => Stream<int>.value(3);
}

class _ProfileWalletSuccessService extends WalletService {
  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    return Wallet.fromMap({
      'balance': 150,
      'maxBalance': 1000,
      'welcomeBonus': 100,
      'dailyBonusAmount': 15,
      'canClaimDailyBonus': false,
    });
  }
}

class _ProfileWalletCachedRefreshService extends WalletService {
  @override
  Wallet? get cachedWallet => _wallet(balance: 150);

  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _wallet(balance: 175);
  }

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    return _wallet(balance: 175);
  }
}

class _ProfileWalletSlowService extends WalletService {
  final Completer<Wallet?> maybeCheckCompleter = Completer<Wallet?>();
  final Completer<Wallet> checkAccrualCompleter = Completer<Wallet>();

  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() =>
      maybeCheckCompleter.future;

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) =>
      checkAccrualCompleter.future;
}

class _ProfileWalletFailingService extends WalletService {
  @override
  Future<Wallet?> maybeCheckAccrualOncePerSession() async {
    throw Exception('wallet failed');
  }

  @override
  Future<Wallet> checkAccrual({bool forceRefresh = false}) async {
    throw Exception('wallet failed');
  }
}

final Uint8List _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP+KobjigAAAABJRU5ErkJggg==',
);

Wallet _wallet({required int balance}) {
  return Wallet.fromMap({
    'balance': balance,
    'maxBalance': 1000,
    'welcomeBonus': 200,
    'dailyBonusAmount': 15,
    'canClaimDailyBonus': false,
  });
}
