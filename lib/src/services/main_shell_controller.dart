import 'package:flutter/foundation.dart';

class MainShellController extends ChangeNotifier {
  MainShellController({int initialIndex = 0}) : _selectedIndex = initialIndex;

  int _selectedIndex;

  int get selectedIndex => _selectedIndex;

  void selectTab(int index) {
    if (_selectedIndex == index) return;
    _selectedIndex = index;
    notifyListeners();
  }
}
