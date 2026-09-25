import 'dart:async';
import 'package:atta/src/features/admin/admin_usage_analytics.dart';
import 'package:atta/src/services/chat_socket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Socket extends ChatSocketService {
  final updates = StreamController<ChatSocketEvent>.broadcast();
  final connections = StreamController<bool>.broadcast();
  int subscriptions = 0;
  @override
  Stream<ChatSocketEvent> get events => updates.stream;
  @override
  Stream<bool> get connectionChanges => connections.stream;
  @override
  void subscribeAnalytics() {
    subscriptions++;
  }
}

Map<String, dynamic> data(int n) => {
      'periods': {
        for (final p in ['today', 'yesterday', 'week', 'month', 'all'])
          p: {
            'guests': n,
            'guestOpens': 2,
            'registeredOpens': 3,
            'totalOpens': 5,
            'messages': 10,
            'activeChats': 1
          },
      }
    };

void main() {
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
        'analytics renders without overflow at $width and supports manual refresh without socket',
        (tester) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: AdminUsageAnalytics(load: () async => data(++calls)),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('Открытия объявлений'), findsOneWidget);
      expect(find.text('Сообщения'), findsOneWidget);
      expect(find.text('Уникальных гостей'), findsOneWidget);
      for (final label in [
        'Вчера',
        '7 дней',
        'Месяц',
        'Всё время',
        'Сегодня'
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      for (final entry in {
        'guests': ['Уникальных гостей'],
        'totalOpens': ['Гости', 'Зарегистрированные', 'Всего'],
        'messages': ['Сообщений', 'Активных диалогов'],
      }.entries) {
        await tester.tap(find.byKey(ValueKey('analytics-${entry.key}')));
        await tester.pumpAndSettle();
        for (final metric in entry.value) {
          expect(find.text(metric), findsOneWidget);
        }
        expect(find.text('Все показатели'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Все показатели'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Обновить аналитику'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('details use each API period without recomputing metrics',
      (tester) async {
    final response = data(0);
    final periods = response['periods'] as Map;
    var n = 100;
    for (final period in periods.values) {
      for (final key in (period as Map).keys.toList()) {
        period[key] = n++;
      }
    }
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: AdminUsageAnalytics(load: () async => response),
    ))));
    await tester.pumpAndSettle();
    for (final block in {
      'guests': ['guests'],
      'totalOpens': ['guestOpens', 'registeredOpens', 'totalOpens'],
      'messages': ['messages', 'activeChats'],
    }.entries) {
      await tester.tap(find.byKey(ValueKey('analytics-${block.key}')));
      await tester.pump();
      for (final period in {
        'today': 'Сегодня',
        'yesterday': 'Вчера',
        'week': '7 дней',
        'month': 'Месяц',
        'all': 'Всё время',
      }.entries) {
        await tester.tap(find.text(period.value));
        await tester.pump();
        for (final metric in block.value) {
          expect(find.text('${periods[period.key][metric]}'), findsOneWidget);
        }
      }
      await tester.tap(find.text('Все показатели'));
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'loading, initial failure, retry, empty and stale refresh in detail',
      (tester) async {
    var pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: AdminUsageAnalytics(load: () => pending.future),
    ))));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analytics-guests')));
    await tester.pump();
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить аналитику.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    pending = Completer<Map<String, dynamic>>();
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(data(0));
    await tester.pumpAndSettle();
    expect(
        find.text('За выбранный период активности пока нет.'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    pending = Completer<Map<String, dynamic>>();
    await tester.tap(find.byTooltip('Обновить аналитику'));
    await tester.pump();
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Показаны последние загруженные данные'),
        findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    pending = Completer<Map<String, dynamic>>();
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    pending.complete(data(42));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('За выбранный период активности пока нет.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'duplicate realtime notifications coalesce into refetch; reconnect resubscribes',
      (tester) async {
    final socket = _Socket();
    var calls = 0;
    await tester.pumpWidget(Provider<ChatSocketService>.value(
        value: socket,
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: AdminUsageAnalytics(load: () async => data(++calls)),
        )))));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey('analytics-guests')));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      socket.updates.add(ChatSocketEvent('analytics_updated', {}));
    }
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('2'), findsOneWidget);
    socket.connections.add(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(calls, 3);
    expect(socket.subscriptions, 2);
    await tester.pumpWidget(const SizedBox());
    await socket.updates.close();
    await socket.connections.close();
  });
}
