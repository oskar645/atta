import 'dart:async';

import 'package:atta/src/features/admin/admin_blocks_screen.dart';
import 'package:atta/src/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('unblock success refreshes list', (tester) async {
    final admin = _FakeBlocksAdminService();

    await _pumpScreen(tester, admin);

    await _unblock(tester);

    expect(admin.unblockedIds, <String>['block-1']);
    expect(admin.unblockReasons, <String>['Апелляция принята']);
    expect(admin.blocksCalls, 2);
    expect(find.text('Пользователь разблокирован'), findsOneWidget);
    expect(find.text('Блокировок в этом фильтре нет.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unblock success with refresh 503 shows neutral refresh error',
      (tester) async {
    final admin = _FakeBlocksAdminService(refreshErrorAfterUnblock: '503');

    await _pumpScreen(tester, admin);

    await _unblock(tester);

    expect(admin.unblockedIds, <String>['block-1']);
    expect(admin.blocksCalls, 2);
    expect(find.textContaining('Ошибка разблокировки'), findsNothing);
    expect(
      find.text('Действие выполнено, но список не удалось обновить'),
      findsOneWidget,
    );
    expect(find.text('Blocked User'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('update block success with refresh 500 does not repeat mutation',
      (tester) async {
    final admin = _FakeBlocksAdminService(refreshErrorAfterUpdate: '500');

    await _pumpScreen(tester, admin);

    await tester.tap(find.text('Сделать бессрочной'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Повторное нарушение');
    await tester.tap(find.text('Сохранить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(admin.updatedIds, <String>['block-1']);
    expect(admin.updatePermanentValues, <bool?>[true]);
    expect(admin.blocksCalls, 2);
    expect(find.text('Срок блокировки изменён'), findsNothing);
    expect(find.textContaining('Ошибка изменения срока'), findsNothing);
    expect(
      find.text('Действие выполнено, но список не удалось обновить'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose during unblock does not use destroyed context',
      (tester) async {
    final unblockCompleter = Completer<Map<String, dynamic>>();
    final admin = _FakeBlocksAdminService(unblockCompleter: unblockCompleter);

    await _pumpScreen(tester, admin);

    await tester.tap(find.text('Разблокировать'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Апелляция принята');
    await tester.tap(find.text('Сохранить'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    unblockCompleter.complete(<String, dynamic>{'ok': true});
    await tester.pumpAndSettle();

    expect(admin.unblockedIds, <String>['block-1']);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeBlocksAdminService admin,
) async {
  await tester.pumpWidget(
    Provider<AdminService>.value(
      value: admin,
      child: const MaterialApp(home: Scaffold(body: AdminBlocksScreen())),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Blocked User'), findsOneWidget);
  expect(find.text('Разблокировать'), findsOneWidget);
}

Future<void> _unblock(WidgetTester tester) async {
  await tester.tap(find.text('Разблокировать'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Апелляция принята');
  await tester.tap(find.text('Сохранить'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

class _FakeBlocksAdminService extends AdminService {
  _FakeBlocksAdminService({
    this.refreshErrorAfterUnblock,
    this.refreshErrorAfterUpdate,
    this.unblockCompleter,
  });

  final String? refreshErrorAfterUnblock;
  final String? refreshErrorAfterUpdate;
  final Completer<Map<String, dynamic>>? unblockCompleter;

  final List<String> unblockedIds = <String>[];
  final List<String> unblockReasons = <String>[];
  final List<String> updatedIds = <String>[];
  final List<bool?> updatePermanentValues = <bool?>[];
  int blocksCalls = 0;
  bool _blocked = true;
  String? _nextRefreshError;

  @override
  Future<Map<String, dynamic>> blocks({
    String? status,
    bool forceRefresh = false,
  }) async {
    blocksCalls += 1;
    if (_nextRefreshError != null) {
      final error = _nextRefreshError!;
      _nextRefreshError = null;
      throw Exception(error);
    }
    return <String, dynamic>{
      'items': _blocked
          ? <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'block-1',
                'status': 'active',
                'permanent': false,
                'reason': 'spam',
                'starts_at': '2026-08-04T10:00:00.000Z',
                'ends_at': '2026-08-11T10:00:00.000Z',
                'user': <String, dynamic>{
                  'id': 'user-1',
                  'display_name': 'Blocked User',
                  'phone': '+79990000000',
                  'avatar_url': '',
                },
              },
            ]
          : const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> unblock(
    String blockId, {
    String? reason,
  }) async {
    unblockedIds.add(blockId);
    unblockReasons.add(reason ?? '');
    _blocked = false;
    _nextRefreshError = refreshErrorAfterUnblock;
    if (unblockCompleter != null) {
      return unblockCompleter!.future;
    }
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> updateBlock(
    String blockId, {
    String? endsAt,
    bool? permanent,
    String? internalNote,
    String? reason,
  }) async {
    updatedIds.add(blockId);
    updatePermanentValues.add(permanent);
    _nextRefreshError = refreshErrorAfterUpdate;
    return <String, dynamic>{'ok': true};
  }
}
