import 'package:flutter/material.dart';

class NavigationProvider extends ChangeNotifier {
  bool _isBottomNavVisible = true;
  bool get isBottomNavVisible => _isBottomNavVisible;

  void setBottomNavVisible(bool visible) {
    if (_isBottomNavVisible != visible) {
      _isBottomNavVisible = visible;
      notifyListeners();
    }
  }

  void toggleBottomNav() {
    _isBottomNavVisible = !_isBottomNavVisible;
    notifyListeners();
  }
}
