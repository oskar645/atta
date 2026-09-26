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

Map<String, dynamic> summaryData(int value) => {
      'periods': {
        for (final period in ['today', 'yesterday', 'week', 'month', 'all'])
          period: {
            'guests': value,
            'guestOpens': value,
            'registeredOpens': value,
            'totalOpens': value,
            'messages': value,
            'activeChats': value,
          },
      },
    };

void main() {
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
        'analytics renders compact cards without a global period at $width',
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
      expect(find.text('Гости'), findsOneWidget);
      for (final key in ['guests', 'totalOpens', 'messages']) {
        final size = tester.getSize(find.byKey(ValueKey('analytics-$key')));
        expect(size.height, lessThan(90));
      }
      expect(find.text('Активность приложения'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      for (final entry in {
        'guests': ['Уникальных гостей'],
        'totalOpens': ['Гости', 'Зарегистрированные', 'Всего'],
        'messages': ['Сообщений', 'Активных диалогов'],
      }.entries) {
        await tester.tap(find.byKey(ValueKey('analytics-${entry.key}')));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.byType(ChoiceChip), findsNWidgets(5));
        for (final metric in entry.value) {
          expect(find.text(metric), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
      }
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final value in [0, 1, 99, 9999]) {
    testWidgets(
        'compact summaries align values right and vertically at 320px for $value',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminUsageAnalytics(load: () async => summaryData(value)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      for (final entry in {
        'guests': 'Гости',
        'totalOpens': 'Открытия объявлений',
        'messages': 'Сообщения',
      }.entries) {
        final card = find.byKey(ValueKey('analytics-${entry.key}'));
        final title =
            find.descendant(of: card, matching: find.text(entry.value));
        final number = find.descendant(of: card, matching: find.text('$value'));
        final cardRect = tester.getRect(card);
        final titleRect = tester.getRect(title);
        final numberRect = tester.getRect(number);

        expect(numberRect.left, greaterThan(titleRect.right));
        expect(numberRect.center.dy, closeTo(cardRect.center.dy, 1));
        expect(numberRect.right, closeTo(cardRect.right - 14, 1));
        expect(cardRect.height, lessThan(90));
      }
      expect(tester.takeException(), isNull);
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
      await tester.pumpAndSettle();
      for (final period in {
        'today': 'Сегодня',
        'yesterday': 'Вчера',
        'week': '7 дней',
        'month': 'Этот месяц',
        'all': 'Всё время',
      }.entries) {
        await tester.tap(find.widgetWithText(ChoiceChip, period.value).last);
        await tester.pump();
        for (final metric in block.value) {
          expect(
              find.text('${periods[period.key][metric]}').last, findsOneWidget);
        }
      }
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('detail periods are independent and dashboard remains unfiltered',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdminUsageAnalytics(load: () async => data(7)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('analytics-guests')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Сегодня'))
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Этот месяц'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('analytics-messages')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Сегодня'))
          .selected,
      isTrue,
    );
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
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNWidgets(3));
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить аналитику.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    pending = Completer<Map<String, dynamic>>();
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    pending.complete(data(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics-guests')));
    await tester.pumpAndSettle();
    expect(
        find.text('За выбранный период активности пока нет.'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
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
