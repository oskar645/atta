import 'package:atta/src/services/api/api_client.dart';

class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      '/auth/login',
      body: {
        'email': email.trim(),
        'password': password,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
    String? phone,
  }) async {
    final response = await _client.post(
      '/auth/signup',
      body: {
        'email': email.trim(),
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> refresh({
    required String refreshToken,
  }) async {
    final response = await _client.post(
      '/auth/refresh',
      body: {
        'refreshToken': refreshToken,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _client.get('/auth/me', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> markAppOpened() async {
    final response = await _client.post('/auth/app-open', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> recordReferralOpen({
    required String referralCode,
  }) async {
    final response = await _client.post(
      '/auth/referrals/open',
      body: {
        'referralCode': referralCode.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> logout({
    required String refreshToken,
  }) async {
    final response = await _client.post(
      '/auth/logout',
      authorized: true,
      body: {
        'refreshToken': refreshToken,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> restoreCredentialRegistrationOptions() async {
    final response = await _client.post(
      '/auth/restore-credentials/registration-options',
      authorized: true,
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> registerRestoreCredential({
    required Map<String, dynamic> responseJson,
  }) async {
    final response = await _client.post(
      '/auth/restore-credentials/register',
      authorized: true,
      body: {
        'response': responseJson,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> restoreCredentialAuthenticationOptions() async {
    final response = await _client.post(
      '/auth/restore-credentials/authentication-options',
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> authenticateWithRestoreCredential({
    required Map<String, dynamic> responseJson,
  }) async {
    final response = await _client.post(
      '/auth/restore-credentials/authenticate',
      body: {
        'response': responseJson,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> revokeRestoreCredential({
    String credentialId = '',
  }) async {
    final response = await _client.post(
      '/auth/restore-credentials/revoke',
      authorized: true,
      body: {
        if (credentialId.trim().isNotEmpty) 'credentialId': credentialId.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> deleteAccount() async {
    final response = await _client.delete('/auth/account', authorized: true);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> startPhoneVerification({
    required String phone,
    required String purpose,
  }) async {
    final response = await _client.post(
      '/auth/phone/start',
      body: {
        'phone': phone,
        'purpose': purpose,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> checkPhoneRegistration({
    required String phone,
  }) async {
    final response = await _client.post(
      '/auth/phone/check-registration',
      body: {
        'phone': phone,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> checkPhoneVerification({
    required String phone,
    required String verificationId,
    required String purpose,
  }) async {
    final response = await _client.post(
      '/auth/phone/check',
      body: {
        'phone': phone,
        'verificationId': verificationId,
        'purpose': purpose,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> signupPhone({
    required String phone,
    required String password,
    required String displayName,
    required String verificationCheckId,
    String referralCode = '',
    String referralId = '',
  }) async {
    final response = await _client.post(
      '/auth/signup-phone',
      body: {
        'phone': phone,
        'password': password,
        'displayName': displayName,
        'verificationCheckId': verificationCheckId,
        if (referralCode.trim().isNotEmpty) 'referralCode': referralCode.trim(),
        if (referralId.trim().isNotEmpty) 'referralId': referralId.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> loginPhone({
    required String phone,
    required String password,
    String verificationCheckId = '',
  }) async {
    final response = await _client.post(
      '/auth/login-phone',
      body: {
        'phone': phone,
        'password': password,
        if (verificationCheckId.trim().isNotEmpty)
          'verificationCheckId': verificationCheckId.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> resetPasswordPhone({
    required String phone,
    required String newPassword,
    required String verificationCheckId,
  }) async {
    final response = await _client.post(
      '/auth/reset-password-phone',
      body: {
        'phone': phone,
        'newPassword': newPassword,
        'verificationCheckId': verificationCheckId,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
