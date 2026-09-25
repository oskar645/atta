import 'web_viewer_device_id_stub.dart'
    if (dart.library.html) 'web_viewer_device_id_web.dart';

Future<String?>? _pendingViewerId;
Future<String?> getWebViewerDeviceId() async {
  final pending = _pendingViewerId ??= getStoredWebViewerDeviceId();
  try {
    return await pending;
  } finally {
    if (identical(_pendingViewerId, pending)) _pendingViewerId = null;
  }
}
