// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:uuid/uuid.dart';

const _storageKey = 'atta.viewerDeviceId';
const _uuid = Uuid();

Future<String?> getStoredWebViewerDeviceId() async {
  try {
    final stored = html.window.localStorage[_storageKey]?.trim();
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    final generated = _uuid.v4();
    html.window.localStorage[_storageKey] = generated;
    return generated;
  } catch (_) {
    return null;
  }
}
