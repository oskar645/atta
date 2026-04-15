import 'dart:convert';

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
  static const String _apiId = '4A57DED4-EF6C-FF72-6F7B-7AF0E542DC74';
  static const String _baseUrl = 'sms.ru';

  Future<CallcheckStartResult> startVerification({
    required String phone,
  }) async {
    final uri = Uri.https(_baseUrl, '/callcheck/add', {
      'api_id': _apiId,
      'phone': phone.replaceAll('+', ''),
      'json': '1',
    });

    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _ensureOk(body);

    return CallcheckStartResult(
      checkId: (body['check_id'] ?? '').toString(),
      callPhone: (body['call_phone'] ?? '').toString(),
      callPhonePretty: (body['call_phone_pretty'] ?? '').toString(),
    );
  }

  Future<CallcheckStatusResult> checkStatus({
    required String checkId,
  }) async {
    final uri = Uri.https(_baseUrl, '/callcheck/status', {
      'api_id': _apiId,
      'check_id': checkId,
      'json': '1',
    });

    final response = await http.get(uri);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    _ensureOk(body);

    return CallcheckStatusResult(
      checkStatus: (body['check_status'] ?? '').toString(),
      checkStatusText: (body['check_status_text'] ?? '').toString(),
    );
  }

  void _ensureOk(Map<String, dynamic> body) {
    final status = (body['status'] ?? '').toString();
    if (status == 'OK') return;

    final statusText = (body['status_text'] ?? 'Не удалось выполнить запрос')
        .toString();
    throw Exception(statusText);
  }
}
