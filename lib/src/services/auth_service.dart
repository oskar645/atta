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
      sessionGeneration: () => _backend.sessionGeneration,
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

  Future<Map<String, dynamic>> startRecoveryEmail(String email) =>
      AuthApi(_apiClient).startRecoveryEmail(email);
  Future<Map<String, dynamic>> verifyRecoveryEmail(
      String challengeId, String code) async {
    final result =
        await AuthApi(_apiClient).verifyRecoveryEmail(challengeId, code);
    await _backend.revalidateCurrentUser();
    return result;
  }

  Future<Map<String, dynamic>> startAccountRecovery(String email) =>
      AuthApi(_apiClient).startAccountRecovery(email);
  Future<Map<String, dynamic>> verifyAccountRecoveryEmail(
          String challengeId, String code) =>
      AuthApi(_apiClient).verifyAccountRecoveryEmail(challengeId, code);
  Future<Map<String, dynamic>> startRecoveryPhone(String token, String phone) =>
      AuthApi(_apiClient).startRecoveryPhone(token, phone);
  Future<Map<String, dynamic>> completeRecoveryPhone(
          String token, String phone, String checkId) =>
      _backend.completeAccountRecovery(
          token: token, phone: phone, checkId: checkId);

  Future<void> ensureInitialized() => _backend.ensureInitialized();

  Future<Map<String, dynamic>> startPasswordless(
      {required String phone}) async {
    final links = DeepLinkService();
    final referralCode = await links.readPendingInviteReferrerId() ?? '';
    final referralId = await links.readPendingInviteReferralId() ?? '';
    return _backend.startPasswordless(
        phone: phone, referralCode: referralCode, referralId: referralId);
  }

  Future<Map<String, dynamic>> checkPasswordless({
    required String challenge,
    required bool Function() isActive,
  }) =>
      _backend.checkPasswordless(challenge: challenge, isActive: isActive);

  Future<void> completePasswordless({
    required String registrationToken,
    required String displayName,
    required bool acceptedLegal,
    required bool acceptedPersonalData,
    required bool Function() isActive,
  }) =>
      _backend.completePasswordless(
        registrationToken: registrationToken,
        displayName: displayName,
        acceptedLegal: acceptedLegal,
        acceptedPersonalData: acceptedPersonalData,
        isActive: isActive,
      );

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
    bool acceptedLegal = false,
    bool acceptedPersonalData = false,
    bool acceptedMarketing = false,
  }) =>
      _backend.signUp(
        email: email,
        password: password,
        displayName: displayName,
        phone: phone,
        acceptedLegal: acceptedLegal,
        acceptedPersonalData: acceptedPersonalData,
        acceptedMarketing: acceptedMarketing,
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

  Future<AuthUser?> syncCurrentUserFromProfile(
    String uid,
    Map<String, dynamic> profile,
  ) =>
      _backend.syncCurrentUserFromProfile(uid, profile);

  Future<AuthUser?> revalidateCurrentUser() => _backend.revalidateCurrentUser();

  Future<AuthUser?> syncBlockStatus() => _backend.revalidateCurrentUser();

  Future<AuthUser?> restoreSessionOnResume({bool force = false}) =>
      _backend.restoreSessionOnResume(force: force);

  Future<void> markAppOpened() async {
    await AuthApi(_apiClient).markAppOpened();
  }

  Future<bool> getMarketingConsent() async {
    final response = await AuthApi(_apiClient).getMarketingConsent();
    return response['accepted'] == true;
  }

  Future<bool> updateMarketingConsent({required bool accepted}) async {
    final response = await AuthApi(_apiClient).updateMarketingConsent(
      accepted: accepted,
    );
    return response['accepted'] == true;
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
    bool acceptedPersonalData = false,
    bool acceptedMarketing = false,
    required String verificationCheckId,
    String referralCode = '',
  }) async {
    final generation = _backend.sessionGeneration;
    final pendingReferralCode = referralCode.trim().isNotEmpty
        ? referralCode.trim()
        : (await DeepLinkService().readPendingInviteReferrerId()) ?? '';
    final pendingReferralId =
        (await DeepLinkService().readPendingInviteReferralId()) ?? '';
    if (generation != _backend.sessionGeneration) {
      return;
    }
    await _backend.signUpWithVerifiedPhone(
      phone: phone,
      password: password,
      displayName: displayName,
      verificationCheckId: verificationCheckId,
      acceptedLegal: acceptedLegal,
      acceptedPersonalData: acceptedPersonalData,
      acceptedMarketing: acceptedMarketing,
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
