import 'dart:convert';

import 'package:atta/src/config/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneAuthBackendService {
  static Uri get _endpoint =>
      Uri.parse('${SupabaseConfig.url}/functions/v1/phone-auth');

  Future<void> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    final body = await _invoke(
      action: 'login',
      payload: {
        'phone': phone,
        'password': password,
      },
    );

    final refreshToken = _extractRefreshToken(body);
    if (refreshToken.isEmpty) {
      throw Exception('Backend не вернул токен сессии');
    }

    await Supabase.instance.client.auth.setSession(refreshToken);
  }

  Future<void> signUpWithVerifiedPhone({
    required String phone,
    required String password,
    required String displayName,
    required bool acceptedLegal,
  }) async {
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
      throw Exception('Backend не вернул токен сессии');
    }

    await Supabase.instance.client.auth.setSession(refreshToken);
  }

  Future<void> resetPasswordWithVerifiedPhone({
    required String phone,
    required String newPassword,
  }) async {
    final body = await _invoke(
      action: 'reset_password',
      payload: {
        'phone': phone,
        'password': newPassword,
      },
    );

    final refreshToken = _extractRefreshToken(body);
    if (refreshToken.isEmpty) {
      throw Exception('Backend не вернул токен сессии');
    }

    await Supabase.instance.client.auth.setSession(refreshToken);
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
    final response = await http.post(
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
    );

    if (response.statusCode == 404) {
      throw Exception(
        'Функция phone-auth ещё не загружена в Supabase. Нужно задеплоить backend.',
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
      throw Exception(error.isEmpty ? 'Ошибка backend' : error);
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
