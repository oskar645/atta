import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _storageKey = 'atta.viewerDeviceId';
const _uuid = Uuid();

Future<String?> getStoredWebViewerDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final generated = _uuid.v4();
    await prefs.setString(_storageKey, generated);
    return generated;
  } catch (_) {
    return null;
  }
}
