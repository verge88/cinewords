import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { system, light, dark, monochrome }

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'preferred_theme_mode';
  AppThemeMode _themeMode = AppThemeMode.system;

  ThemeProvider() {
    _loadTheme();
  }

  AppThemeMode get themeMode => _themeMode;

  ThemeMode get flutterThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.monochrome:
        return ThemeMode.dark; // We'll handle monochrome by overriding the theme
      case AppThemeMode.system:
      default:
        return ThemeMode.system;
    }
  }

  bool get isMonochrome => _themeMode == AppThemeMode.monochrome;

  void setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_themeKey);
      if (savedMode != null) {
        _themeMode = AppThemeMode.values.firstWhere(
          (e) => e.name == savedMode,
          orElse: () => AppThemeMode.system,
        );
        notifyListeners();
      }
    } catch (_) {
      // Ignore if prefs fail
    }
  }
}
