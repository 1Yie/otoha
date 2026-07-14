import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocaleController extends ChangeNotifier {
  AppLocaleController({Locale? initialLocale})
    : _locale = _supportedLocaleFor(
        initialLocale ?? PlatformDispatcher.instance.locale,
      );

  static const supportedLocales = <Locale>[Locale('en'), Locale('zh')];

  Locale _locale;

  Locale get locale => _locale;
  String get youtubeLanguage => _locale.languageCode == 'zh' ? 'zh-CN' : 'en';

  void select(Locale locale) {
    final supported = _supportedLocaleFor(locale);
    if (_locale == supported) {
      return;
    }
    _locale = supported;
    notifyListeners();
  }

  static Locale _supportedLocaleFor(Locale locale) =>
      locale.languageCode.toLowerCase() == 'zh'
      ? const Locale('zh')
      : const Locale('en');
}
