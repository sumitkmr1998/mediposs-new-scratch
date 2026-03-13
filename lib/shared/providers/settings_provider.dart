import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/objectbox_service.dart';

class SettingsProvider extends ChangeNotifier {
  late AppSettings _settings;

  AppSettings get settings => _settings;

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  void load() {
    _settings = ObjectBoxService.instance.settings;
    notifyListeners();
  }

  void save(AppSettings updated) {
    updated.id = (_settings.id == 0) ? 0 : _settings.id;
    ObjectBoxService.instance.settingsBox.put(updated);
    _settings = updated;
    notifyListeners();
  }
}
