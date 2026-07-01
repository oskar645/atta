import 'package:atta/src/features/auth/auth_gate.dart';
import 'package:atta/src/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('/auth/me is not retriggered by build loop in AuthGate',
      (tester) async {
    final auth = _FakeAuthService();

    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: const MaterialApp(
          home: AuthGate(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(auth.ensureInitializedCalls, 1);
  });
}

class _FakeAuthService extends AuthService {
  int ensureInitializedCalls = 0;

  @override
  Future<void> ensureInitialized() async {
    ensureInitializedCalls += 1;
  }
}
