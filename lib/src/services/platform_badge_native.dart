import 'dart:io';
import 'package:app_badge_plus/app_badge_plus.dart';

Future<bool> isBadgeSupported() async =>
    (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) &&
    await AppBadgePlus.isSupported();
Future<void> updateBadge(int count) => AppBadgePlus.updateBadge(count);
