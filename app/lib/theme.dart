import 'package:flutter/material.dart';

/// LifeWave palette, sampled from official LifeWave sources only
/// (ASSETS.md palette table — do not substitute other blues).
abstract class LwColors {
  static const Color primary = Color(0xFF194F90); // nautical-blue
  static const Color accent = Color(0xFF5EB3E4); // sanctuary-blue
  static const Color text = Color(0xFF373F41); // anthracite-grey
  static const Color deepNavy = Color(0xFF0E3058); // sampled deep navy
  static const Color tint = Color(0xFFECF5FA); // pale blue tint
  static const Color white = Color(0xFFFFFFFF);
}

/// App-wide constants. The version string matches pubspec.yaml
/// (version: 1.0.0+1) — package_info_plus is deliberately not a dependency
/// in M1 (minimal dependency rule), so this constant is the source the
/// Diagnostics/About screens show; bump it with the pubspec version.
abstract class AppInfo {
  static const String appName = 'LifeWave AI';
  static const String version = '1.0.0';
  static const int buildNumber = 1;
  static const String versionLabel = 'Version 1.1.0 (build 2)';

  /// SPEC §7.12 guardrail line — exact wording, shown in About and once
  /// on first run.
  static const String independentToolLine =
      'An independent Brand Partner tool — not an official LifeWave, Inc. app.';
}

ThemeData buildLifewaveTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LwColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: LwColors.primary,
    onPrimary: LwColors.white,
    secondary: LwColors.accent,
    onSecondary: LwColors.deepNavy,
    tertiary: LwColors.deepNavy,
    surface: LwColors.white,
    onSurface: LwColors.text,
    surfaceContainerHighest: LwColors.tint,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LwColors.tint,
    textTheme: ThemeData.light()
        .textTheme
        .apply(bodyColor: LwColors.text, displayColor: LwColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: LwColors.primary,
      foregroundColor: LwColors.white,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: LwColors.white,
      indicatorColor: LwColors.tint,
    ),
    cardTheme: const CardTheme(color: LwColors.white, elevation: 1),
  );
}
