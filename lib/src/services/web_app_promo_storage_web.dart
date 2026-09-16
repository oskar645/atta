import 'package:web/web.dart' as web;

const String _key = 'atta.webAppPromo.dismissedAt';

int? readWebAppPromoDismissedAt() {
  final raw = web.window.localStorage.getItem(_key);
  if (raw == null || raw.trim().isEmpty) return null;
  return int.tryParse(raw);
}

void writeWebAppPromoDismissedAt(int timestamp) {
  web.window.localStorage.setItem(_key, '$timestamp');
}
