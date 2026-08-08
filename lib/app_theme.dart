import 'package:flutter/material.dart';

class AppTheme {
  static const _dark = Color(0xFF050505);
  static const _surface = Color(0xFF121212);
  static const _surface2 = Color(0xFF1d1d1d);
  static const _surface3 = Color(0xFF2a2a2a);
  static const _text = Color(0xFFf5f5f5);
  static const _textDim = Color(0xFFa8a8a8);
  static const _textFaint = Color(0xFF666666);
  static const _accent = Color(0xFF4fc3f7);
  static const _accentGlow = Color(0x404fc3f7);
  static const _danger = Color(0xFFef5350);
  static const _success = Color(0xFF66bb6a);
  static const _warning = Color(0xFFffa726);
  static const _vinyl = Color(0xFF0c0c0c);

  static const _lightBg = Color(0xFFf0f0f0);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurface2 = Color(0xFFe9e9e9);
  static const _lightSurface3 = Color(0xFFdadada);
  static const _lightText = Color(0xFF1a1a1a);
  static const _lightTextDim = Color(0xFF5a5a5a);
  static const _lightAccent = Color(0xFF0288d1);

  static ThemeData dark() {
    return _build(
      bg: _dark,
      surface: _surface,
      surface2: _surface2,
      surface3: _surface3,
      text: _text,
      textDim: _textDim,
      textFaint: _textFaint,
      accent: _accent,
      accentGlow: _accentGlow,
      danger: _danger,
      warning: _warning,
      vinyl: _vinyl,
      isDark: true,
    );
  }

  static ThemeData light() {
    return _build(
      bg: _lightBg,
      surface: _lightSurface,
      surface2: _lightSurface2,
      surface3: _lightSurface3,
      text: _lightText,
      textDim: _lightTextDim,
      textFaint: _textFaint,
      accent: _lightAccent,
      accentGlow: const Color(0x330288d1),
      danger: const Color(0xFFd32f2f),
      warning: const Color(0xFFef6c00),
      vinyl: const Color(0xFF1a1a1a),
      isDark: false,
    );
  }

  static ThemeData _build({
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color surface3,
    required Color text,
    required Color textDim,
    required Color textFaint,
    required Color accent,
    required Color accentGlow,
    required Color danger,
    required Color warning,
    required Color vinyl,
    required bool isDark,
  }) {
    // Roboto is Flutter's standard Material font — clean, modern, highly legible.
    // It is bundled with the Flutter engine (including flutter-pi), so it works
    // on every platform without additional font files or network access.
    const font = 'Roboto';
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: font,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: isDark ? bg : surface,
        secondary: accent,
        onSecondary: isDark ? bg : surface,
        surface: surface,
        onSurface: text,
        error: danger,
        onError: isDark ? const Color(0xFFCF6679) : const Color(0xFFB3266E),
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: text, fontSize: 14, fontFamily: font),
        bodySmall: TextStyle(color: textDim, fontSize: 12, fontFamily: font),
        labelSmall: TextStyle(color: textDim, fontSize: 10, fontFamily: font),
        titleMedium:
            TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: font),
      ),
      extensions: <ThemeExtension<dynamic>>[
        SonosColors(
          bg: bg,
          surface: surface,
          surface2: surface2,
          surface3: surface3,
          text: text,
          textDim: textDim,
          textFaint: textFaint,
          accent: accent,
          accentGlow: accentGlow,
          danger: danger,
          success: _success,
          warning: warning,
          vinyl: vinyl,
          glass: isDark ? const Color(0xD9141414) : const Color(0xD9FFFFFF),
          glassBorder: isDark ? const Color(0x14FFFFFF) : const Color(0x14000000),
          scrim: isDark ? const Color(0xA6000000) : const Color(0x73000000),
        ),
      ],
    );
  }
}

class SonosColors extends ThemeExtension<SonosColors> {
  final Color bg, surface, surface2, surface3;
  final Color text, textDim, textFaint;
  final Color accent, accentGlow;
  final Color danger, success, warning;
  final Color vinyl, glass, glassBorder, scrim;

  const SonosColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentGlow,
    required this.danger,
    required this.success,
    required this.warning,
    required this.vinyl,
    required this.glass,
    required this.glassBorder,
    required this.scrim,
  });

  @override
  SonosColors copyWith() => this;

  @override
  SonosColors lerp(covariant SonosColors? other, double t) => this;
}

extension SonosColorsX on BuildContext {
  SonosColors get c => Theme.of(this).extension<SonosColors>()!;
}
