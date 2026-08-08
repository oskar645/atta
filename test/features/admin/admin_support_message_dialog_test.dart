import 'dart:async';

import 'package:atta/src/features/admin/admin_support_message_dialog.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('admin support dialog blocks empty message', (tester) async {
    final admin = _FakeAdminService();
    await tester.pumpWidget(_buildApp(admin));

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отправить'));
    await tester.pump();

    expect(find.text('Введите сообщение'), findsOneWidget);
    expect(admin.sendCalls, 0);
  });

  testWidgets('admin support dialog protects from double send', (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    final admin = _FakeAdminService(onSend: () => completer.future);
    await tester.pumpWidget(_buildApp(admin));

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Здравствуйте');
    await tester.tap(find.text('Отправить'));
    await tester.pump();
    await tester.tap(find.text('Отправить'));
    await tester.pump();

    expect(admin.sendCalls, 1);

    completer.complete(<String, dynamic>{
      'ticketId': 'ticket-1',
      'messageId': 'message-1',
    });
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}

Widget _buildApp(_FakeAdminService admin) {
  return Provider<AdminService>.value(
    value: admin,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showAdminSupportMessageDialog(
                context: context,
                userId: 'user-1',
                userName: 'Иван',
                userHandle: '+7 *** *** 0000',
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FakeAdminService extends AdminService {
  _FakeAdminService({this.onSend});

  final Future<Map<String, dynamic>> Function()? onSend;
  int sendCalls = 0;

  @override
  Future<Map<String, dynamic>> sendSupportMessageToUser({
    required String userId,
    required String message,
    required String idempotencyKey,
  }) async {
    sendCalls += 1;
    final handler = onSend;
    if (handler != null) return handler();
    return <String, dynamic>{
      'ticketId': 'ticket-1',
      'messageId': 'message-1',
    };
  }
}
