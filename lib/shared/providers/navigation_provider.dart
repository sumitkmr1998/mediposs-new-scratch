import 'package:flutter/material.dart';

class NavigationProvider extends ChangeNotifier {
  bool _isBottomNavVisible = true;
  bool get isBottomNavVisible => _isBottomNavVisible;

  String _activeDestId = 'dashboard';
  String get activeDestId => _activeDestId;

  void selectDestination(String destId) {
    if (_activeDestId != destId) {
      _activeDestId = destId;
      notifyListeners();
    }
  }

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
