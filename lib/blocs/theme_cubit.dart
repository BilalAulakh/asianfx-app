import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<bool> {
  ThemeCubit() : super(true) {
    _loadTheme();
  }

  static const String _key = 'is_dark_mode';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    emit(prefs.getBool(_key) ?? true);
  }

  Future<void> toggleTheme() async {
    final next = !state;
    emit(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
  }

  Future<void> setDark(bool dark) async {
    emit(dark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
  }
}
