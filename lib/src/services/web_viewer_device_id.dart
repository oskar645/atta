import 'web_viewer_device_id_stub.dart'
    if (dart.library.html) 'web_viewer_device_id_web.dart';

Future<String?> getWebViewerDeviceId() => getStoredWebViewerDeviceId();
