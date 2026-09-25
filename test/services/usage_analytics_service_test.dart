import 'package:atta/src/services/web_viewer_device_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'reuses existing random installation ID across calls and browser/mobile storage reload',
      () async {
    const id = '7f965d60-4fa6-4bfc-9258-c1208bce89d6';
    SharedPreferences.setMockInitialValues({'atta.viewerDeviceId': id});
    expect(await getWebViewerDeviceId(), id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await getWebViewerDeviceId(), id);
  });
  test('simultaneous initial requests create a single stable UUID', () async {
    SharedPreferences.setMockInitialValues({});
    final ids =
        await Future.wait(List.generate(20, (_) => getWebViewerDeviceId()));
    expect(ids.toSet().length, 1);
    expect(
        ids.first,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(await getWebViewerDeviceId(), ids.first);
  });
}
