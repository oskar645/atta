import 'package:flutter/material.dart';
import 'admin_ads_tab.dart';
import 'admin_top_banners_tab.dart';

class AdminAdvertisingTab extends StatelessWidget {
  const AdminAdvertisingTab({super.key});
  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 2,
        child: Column(children: [
          TabBar(tabs: [
            Tab(text: 'Верхние баннеры'),
            Tab(text: 'Баннеры под поиском')
          ]),
          Expanded(
              child:
                  TabBarView(children: [AdminTopBannersTab(), AdminAdsTab()])),
        ]),
      );
}
