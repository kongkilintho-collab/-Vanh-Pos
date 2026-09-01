import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localePrefsKey = 'app_locale';

/// Supported UI languages. English is the default; Lao is the primary
/// localization target for this deployment.
const supportedAppLocales = [Locale('en'), Locale('lo')];

/// Holds the user's chosen UI language and persists it across restarts
/// (including a browser refresh on Web, via shared_preferences' web
/// implementation backed by localStorage).
class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('en')) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_localePrefsKey);
    if (saved != null &&
        supportedAppLocales.any((l) => l.languageCode == saved)) {
      state = Locale(saved);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localePrefsKey, locale.languageCode);
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>(
      (ref) => LocaleController(),
    );
