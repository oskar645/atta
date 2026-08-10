import 'package:atta/src/features/admin/admin_ads_tab.dart';
import 'package:atta/src/models/feed_ad.dart';
import 'package:atta/src/services/feed_ads_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'feed ads tab loads once and does not poll or reload on rebuild/dispose',
    (tester) async {
      final feedAds = _FakeFeedAdsService();

      await tester.pumpWidget(_Host(feedAds: feedAds));
      await tester.pumpAndSettle();

      expect(feedAds.loadAllAdsCalls, 1);
      expect(find.text('Рекламы пока нет. Можно добавить баннер вручную.'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rebuild-host')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();

      expect(feedAds.loadAllAdsCalls, 1);

      await tester.tap(find.byKey(const ValueKey('hide-ads-tab')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();

      expect(feedAds.loadAllAdsCalls, 1);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host({required this.feedAds});

  final FeedAdsService feedAds;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool _showAdsTab = true;
  int _rebuildNonce = 0;

  @override
  Widget build(BuildContext context) {
    return Provider<FeedAdsService>.value(
      value: widget.feedAds,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Row(
                children: [
                  Text('rebuild $_rebuildNonce'),
                  TextButton(
                    key: const ValueKey('rebuild-host'),
                    onPressed: () => setState(() => _rebuildNonce++),
                    child: const Text('Rebuild'),
                  ),
                  TextButton(
                    key: const ValueKey('hide-ads-tab'),
                    onPressed: () => setState(() => _showAdsTab = false),
                    child: const Text('Hide'),
                  ),
                ],
              ),
              Expanded(
                child: _showAdsTab ? const AdminAdsTab() : const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FakeFeedAdsService extends FeedAdsService {
  int loadAllAdsCalls = 0;

  @override
  Future<List<FeedAd>> loadAllAds({String placement = 'home'}) async {
    loadAllAdsCalls += 1;
    return const <FeedAd>[];
  }
}
