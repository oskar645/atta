import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.light;
  bool _loaded = false;

  ThemeService() {
    _restore();
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  bool get isLoaded => _loaded;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggle(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, dark ? 'dark' : 'light');
  }
}
