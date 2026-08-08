import 'package:atta/src/services/api/admin_api.dart';
import 'package:atta/src/services/api/api_client.dart';
import 'package:atta/src/services/api/auth_api.dart';
import 'package:atta/src/services/api/chats_api.dart';
import 'package:atta/src/services/api/listings_api.dart';
import 'package:atta/src/services/api/notifications_api.dart';
import 'package:atta/src/services/api/users_api.dart';
import 'package:atta/src/services/auth/auth_models.dart';
import 'package:atta/src/services/auth/token_storage.dart';
import 'package:atta/src/services/backend_auth_service.dart';
import 'package:atta/src/services/deep_link_service.dart';

export 'package:atta/src/services/auth/auth_models.dart';

class AuthService {
  AuthService()
      : _backend = BackendAuthService(
          authApi: AuthApi(_apiClient),
          usersApi: UsersApi(_apiClient),
          tokenStorage: _storage,
        ),
        listingsApi = ListingsApi(_apiClient),
        chatsApi = ChatsApi(_apiClient),
        notificationsApi = NotificationsApi(_apiClient),
        adminApi = AdminApi(_apiClient) {
    ApiClient.configureAuthHandlers(
      onRefreshSession: _backend.refreshSession,
      onSessionExpired: _backend.expireSession,
      onAwaitAuthorizedSession: _backend.awaitPrivateAuthReady,
      onAccountBlocked: _backend.revalidateCurrentUser,
    );
  }

  static final TokenStorage _storage = TokenStorage();
  static final ApiClient _apiClient = ApiClient(tokenStorage: _storage);
  final BackendAuthService _backend;

  final ListingsApi listingsApi;
  final ChatsApi chatsApi;
  final NotificationsApi notificationsApi;
  final AdminApi adminApi;

  bool get useTimewebBackend => true;
  Stream<AuthSessionEvent> get onAuthStateChange => _backend.onAuthStateChange;
  AuthUser? get currentUser => _backend.currentUser;
  bool get isAuthenticated => _backend.isSignedIn;

  Future<void> ensureInitialized() => _backend.ensureInitialized();

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) =>
      _backend.signIn(email: email, password: password);

  Future<AuthUser> signUp({
    required String email,
    required String password,
    String? displayName,
    String? phone,
  }) =>
      _backend.signUp(
        email: email,
        password: password,
        displayName: displayName,
        phone: phone,
      );

  Future<void> signOut() => _backend.signOut();

  Future<void> deleteAccount() => _backend.deleteAccount();

  Future<void> updateAuthMetadata({
    String? displayName,
    String? photoUrl,
  }) =>
      _backend.updateProfile(
        displayName: displayName,
        photoUrl: photoUrl,
      );

  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
  }) =>
      updateAuthMetadata(displayName: displayName, photoUrl: photoUrl);

  Future<AuthUser?> revalidateCurrentUser() => _backend.revalidateCurrentUser();

  Future<AuthUser?> syncBlockStatus() => _backend.revalidateCurrentUser();

  Future<AuthUser?> restoreSessionOnResume({bool force = false}) =>
      _backend.restoreSessionOnResume(force: force);

  Future<void> markAppOpened() async {
    await AuthApi(_apiClient).markAppOpened();
  }

  Future<Map<String, dynamic>> recordReferralOpen({
    required String referralCode,
  }) =>
      AuthApi(_apiClient).recordReferralOpen(referralCode: referralCode);

  Future<void> signInWithPhone({
    required String phone,
    required String password,
    String verificationCheckId = '',
  }) =>
      _backend.signInWithPhone(
        phone: phone,
        password: password,
        verificationCheckId: verificationCheckId,
      );

  Future<void> signUpWithVerifiedPhone({
    required String phone,
    required String password,
    required String displayName,
    required bool acceptedLegal,
    required String verificationCheckId,
    String referralCode = '',
  }) async {
    final pendingReferralCode = referralCode.trim().isNotEmpty
        ? referralCode.trim()
        : (await DeepLinkService().readPendingInviteReferrerId()) ?? '';
    final pendingReferralId =
        (await DeepLinkService().readPendingInviteReferralId()) ?? '';
    await _backend.signUpWithVerifiedPhone(
      phone: phone,
      password: password,
      displayName: displayName,
      verificationCheckId: verificationCheckId,
      referralCode: pendingReferralCode,
      referralId: pendingReferralId,
    );
    if (pendingReferralCode.isNotEmpty) {
      await DeepLinkService().clearPendingInviteReferrerId();
    }
  }

  Future<void> resetPasswordWithVerifiedPhone({
    required String phone,
    required String newPassword,
    required String verificationCheckId,
  }) =>
      _backend.resetPasswordWithVerifiedPhone(
        phone: phone,
        newPassword: newPassword,
        verificationCheckId: verificationCheckId,
      );

  Future<bool> isPhoneRegistered({
    required String phone,
  }) =>
      _backend.isPhoneRegistered(phone: phone);

  Future<PhoneVerificationStartResult> startPhoneVerification({
    required String phone,
    required String purpose,
  }) =>
      _backend.startPhoneVerification(
        phone: phone,
        purpose: purpose,
      );

  Future<PhoneVerificationCheckResult> checkPhoneVerification({
    required String phone,
    required String verificationId,
    required String purpose,
  }) =>
      _backend.checkPhoneVerification(
        phone: phone,
        verificationId: verificationId,
        purpose: purpose,
      );

  Future<void> linkEmailToCurrentUser({
    required String email,
  }) =>
      _backend.linkEmailToCurrentUser(email: email);

  String userMessageForError(Object error, {bool isSignIn = false}) {
    return _backend.userMessageForError(error, isSignIn: isSignIn);
  }
}
