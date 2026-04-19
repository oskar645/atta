import 'dart:convert';

import 'package:atta/src/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneAuthBackendException implements Exception {
  final String message;
  final String? technicalDetails;

  const PhoneAuthBackendException(this.message, {this.technicalDetails});

  @override
  String toString() => message;
}

class PhoneAuthBackendService {
  static Uri get _endpoint =>
      Uri.parse('${SupabaseConfig.url}/functions/v1/phone-auth');

  String userMessageForError(Object error, {bool isSignIn = false}) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final msg = raw.toLowerCase();

    if (msg.contains('user already registered') ||
        msg.contains('уже зарегистрирован')) {
      return isSignIn
          ? 'Неверный номер телефона или пароль.'
          : 'Этот номер уже зарегистрирован. Попробуйте войти.';
    }
    if (msg.contains('invalid login credentials') ||
        msg.contains('неверный номер телефона или пароль')) {
      return 'Неверный номер телефона или пароль.';
    }
    if (msg.contains('введите не менее 8 цифр') ||
        msg.contains('minimum 8 digits')) {
      return 'Введите не менее 8 цифр.';
    }
    if (msg.contains('permission denied for schema public')) {
      return 'Не удалось завершить регистрацию. Попробуйте еще раз.';
    }
    if (msg.contains('phone signups are disabled')) {
      return 'Телефонная регистрация сейчас временно недоступна.';
    }
    if (msg.contains('sms provider is not configured') ||
        msg.contains('twilio')) {
      return 'Сервис подтверждения телефона сейчас недоступен.';
    }
    if (msg.contains('failed host lookup') ||
        msg.contains('socketexception') ||
        msg.contains('clientexception')) {
      return 'Нет соединения с сервером. Проверьте интернет, приложение попробует еще раз.';
    }
    if (msg.contains('backend') ||
        msg.contains('schema public') ||
        msg.contains('permission denied')) {
      return 'Не удалось выполнить операцию. Попробуйте еще раз.';
    }

    return 'Произошла ошибка. Попробуйте еще раз.';
  }

  Future<bool> isPhoneRegistered({
    required String phone,
  }) async {
    final body = await _invoke(
      action: 'check_registration',
      payload: {
        'phone': phone,
      },
    );

    return body['registered'] == true;
  }

  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    debugPrint('Phone auth login: invoking backend for $phone');
    final body = await _invoke(
      action: 'login',
      payload: {
        'phone': phone,
        'password': password,
      },
    );

    final refreshToken = _extractRefreshToken(body);
    if (refreshToken.isEmpty) {
      throw const PhoneAuthBackendException(
        'Не удалось открыть сессию. Попробуйте еще раз.',
        technicalDetails: 'Backend did not return refresh token for login.',
      );
    }

    debugPrint('Phone auth login: backend ok, setting session');
    await Supabase.instance.client.auth
        .setSession(refreshToken)
        .timeout(const Duration(seconds: 20));
    debugPrint('Phone auth login: session ready');
  }

  Future<void> signUpWithVerifiedPhone({
    required String phone,
    required String password,
    required String displayName,
    required bool acceptedLegal,
  }) async {
    debugPrint(
      'Phone auth signup: invoking backend for $phone, nameLen=${displayName.trim().length}, passLen=${password.trim().length}',
    );
    final body = await _invoke(
      action: 'signup',
      payload: {
        'phone': phone,
        'password': password,
        'display_name': displayName,
        'accepted_legal': acceptedLegal,
      },
    );

    final refreshToken = _extractRefreshToken(body);
    if (refreshToken.isEmpty) {
      throw const PhoneAuthBackendException(
        'Не удалось открыть сессию. Попробуйте еще раз.',
        technicalDetails: 'Backend did not return refresh token for signup.',
      );
    }

    debugPrint('Phone auth signup: backend ok, setting session');
    await Supabase.instance.client.auth
        .setSession(refreshToken)
        .timeout(const Duration(seconds: 20));
    debugPrint('Phone auth signup: session ready');
  }

  Future<void> resetPasswordWithVerifiedPhone({
    required String phone,
    required String newPassword,
  }) async {
    debugPrint('Phone auth reset_password: invoking backend for $phone');
    final body = await _invoke(
      action: 'reset_password',
      payload: {
        'phone': phone,
        'password': newPassword,
      },
    );

    final refreshToken = _extractRefreshToken(body);
    if (refreshToken.isEmpty) {
      throw const PhoneAuthBackendException(
        'Не удалось открыть сессию. Попробуйте еще раз.',
        technicalDetails:
            'Backend did not return refresh token for password reset.',
      );
    }

    debugPrint('Phone auth reset_password: backend ok, setting session');
    await Supabase.instance.client.auth
        .setSession(refreshToken)
        .timeout(const Duration(seconds: 20));
    debugPrint('Phone auth reset_password: session ready');
  }

  Future<void> linkEmailToCurrentUser({
    required String email,
  }) async {
    await _invoke(
      action: 'link_email',
      payload: {
        'email': email.trim(),
      },
      accessToken: Supabase.instance.client.auth.currentSession?.accessToken,
    );
  }

  Future<Map<String, dynamic>> _invoke({
    required String action,
    required Map<String, dynamic> payload,
    String? accessToken,
  }) async {
    final response = await http
        .post(
          _endpoint,
          headers: {
            'Content-Type': 'application/json',
            'apikey': SupabaseConfig.anonKey,
            'Authorization':
                'Bearer ${(accessToken == null || accessToken.trim().isEmpty) ? SupabaseConfig.anonKey : accessToken.trim()}',
          },
          body: jsonEncode({
            'action': action,
            ...payload,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 404) {
      throw const PhoneAuthBackendException(
        'Телефонная регистрация сейчас недоступна.',
        technicalDetails: 'Function phone-auth is missing in Supabase.',
      );
    }

    final raw = response.body.trim();
    final body = raw.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = (body['error'] ?? body['message'] ?? 'Ошибка backend')
          .toString()
          .trim();
      final technical = error.isEmpty ? 'Ошибка backend' : error;
      throw PhoneAuthBackendException(
        userMessageForError(technical, isSignIn: action == 'login'),
        technicalDetails: technical,
      );
    }

    return body;
  }

  String _extractRefreshToken(Map<String, dynamic> body) {
    final direct = (body['refresh_token'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final session = body['session'];
    if (session is Map<String, dynamic>) {
      return (session['refresh_token'] ?? '').toString().trim();
    }

    return '';
  }
}
