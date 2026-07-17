import 'package:flutter/material.dart';

class AppMetrics {
  const AppMetrics._();

  static const unit = 8.0;
  static const titleBarHeight = 56.0;
  static const sidebarWidth = 240.0;
  static const playerHeight = 96.0;
  static const workspacePadding = 40.0;
  static const panelWidth = 368.0;
  static const radius = 8.0;
}

class OtohaColors {
  const OtohaColors._();

  static const canvas = Color(0xFF111210);
  static const surface = Color(0xFF191A17);
  static const surfaceRaised = Color(0xFF22231F);
  static const border = Color(0xFF2B2D28);
  static const divider = Color(0xFF22241F);
  static const text = Color(0xFFF1F2EC);
  static const mutedText = Color(0xFFA3A59C);
  static const accent = Color(0xFFB6F26D);
}

ThemeData buildOtohaTheme() {
  final colorScheme = const ColorScheme.dark(
    primary: OtohaColors.accent,
    onPrimary: Color(0xFF1A210F),
    surface: OtohaColors.surface,
    onSurface: OtohaColors.text,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'MiSans',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: OtohaColors.canvas,
    canvasColor: OtohaColors.canvas,
    dividerColor: OtohaColors.divider,
    dividerTheme: const DividerThemeData(
      color: OtohaColors.divider,
      space: 1,
      thickness: 1,
    ),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: OtohaColors.text,
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: OtohaColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: OtohaColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(color: OtohaColors.text, fontSize: 14),
      bodySmall: TextStyle(color: OtohaColors.mutedText, fontSize: 13),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: OtohaColors.surfaceRaised,
        borderRadius: BorderRadius.all(Radius.circular(AppMetrics.radius)),
      ),
      textStyle: TextStyle(color: OtohaColors.text, fontSize: 12),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: OtohaColors.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppMetrics.radius)),
        borderSide: BorderSide(color: OtohaColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppMetrics.radius)),
        borderSide: BorderSide(color: OtohaColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppMetrics.radius)),
        borderSide: BorderSide(color: OtohaColors.accent, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: OtohaColors.accent,
      inactiveTrackColor: OtohaColors.border,
      thumbColor: OtohaColors.accent,
      overlayColor: Color(0x33B6F26D),
      trackHeight: 3,
    ),
  );
}
