import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Theme State ───────────────────────────────────────────────────────────────
class ThemeNotifier extends StateNotifier<bool> {
  ThemeNotifier() : super(true) { // true = dark mode default
    _loadTheme();
  }

  static const String _key = 'is_dark_mode';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> toggleTheme() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }

  Future<void> setDark(bool dark) async {
    state = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, bool>((ref) {
  return ThemeNotifier();
});
