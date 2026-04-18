import 'dart:convert';

import 'package:atta/src/config/supabase_config.dart';
import 'package:http/http.dart' as http;

class CallcheckStartResult {
  final String checkId;
  final String callPhone;
  final String callPhonePretty;

  const CallcheckStartResult({
    required this.checkId,
    required this.callPhone,
    required this.callPhonePretty,
  });
}

class CallcheckStatusResult {
  final String checkStatus;
  final String checkStatusText;

  const CallcheckStatusResult({
    required this.checkStatus,
    required this.checkStatusText,
  });

  bool get isConfirmed => checkStatus == '401';
  bool get isPending => checkStatus == '400';
}

class CallcheckService {
  static Uri get _endpoint =>
      Uri.parse('${SupabaseConfig.url}/functions/v1/phone-auth');

  Future<CallcheckStartResult> startVerification({
    required String phone,
  }) async {
    final body = await _invoke(
      action: 'callcheck_start',
      payload: {
        'phone': phone,
      },
    );

    return CallcheckStartResult(
      checkId: (body['check_id'] ?? '').toString(),
      callPhone: (body['call_phone'] ?? '').toString(),
      callPhonePretty: (body['call_phone_pretty'] ?? '').toString(),
    );
  }

  Future<CallcheckStatusResult> checkStatus({
    required String checkId,
  }) async {
    final body = await _invoke(
      action: 'callcheck_status',
      payload: {
        'check_id': checkId,
      },
    );

    return CallcheckStatusResult(
      checkStatus: (body['check_status'] ?? '').toString(),
      checkStatusText: (body['check_status_text'] ?? '').toString(),
    );
  }

  Future<Map<String, dynamic>> _invoke({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final response = await http.post(
      _endpoint,
      headers: {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
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

    final status = (body['status'] ?? '').toString();
    if (status.isNotEmpty && status != 'OK') {
      final statusText = (body['status_text'] ?? 'Не удалось выполнить запрос')
          .toString()
          .trim();
      throw Exception(statusText.isEmpty ? 'Не удалось выполнить запрос' : statusText);
    }

    return body;
  }
}
