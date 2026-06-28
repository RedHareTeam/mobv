import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand ───────────────────────────────────────────────────
  static const primary = Color(0xFF5865F2);
  static const primaryBg = Color(0xFFEFF1FF);

  static const secondary = Color(0xFF5AD6C0);
  static const secondaryBg = Color(0xFFEAFBF8);

  static const accent = Color(0xFF2E9BC8);
  static const accentBg = Color(0xFFEAF6FB);

  // ── Neutral ──────────────────────────────────────────────────
  static const bg = Color(0xFFF4F5F8);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1C2350);
  static const textBody = Color(0xFF3A4170);
  static const textMuted = Color(0xFF9AA0BD);
  static const border = Color(0xFFE6E8F0);

  // ── 상태별 색상 ──────────────────────────────────────────────
  static const drawing = primary;
  static const voting = accent;
  static const confirmed = Color(0xFF2BB673);

  // ── 비활성 ───────────────────────────────────────────────────
  static const disabled = Color(0xFFB8BCD0);
  static const disabledBg = Color(0xFFEDEEFA);

  // ── 에러·경고 ────────────────────────────────────────────────
  static const error = Color(0xFFE5484D);
  static const warning = Color(0xFFF2A63B);
  static const warningDark = Color(0xFFB56F00);

  // ── 그래디언트 끝 색상 ───────────────────────────────────────
  static const gradientEnd = accent;

  // ── 카드 배경 그래디언트 ─────────────────────────────────────
  static const cardGradientStart = primaryBg;
  static const cardGradientEnd = secondaryBg;

  // ── 히트맵 밀도 색상 ────────────────────────────────────────
  static const heatmapLow = Color(0xFF5AD6C0);
  static const heatmapMid = Color(0xFF5865F2);
  static const heatmapHigh = Color(0xFF2E9BC8);

  // ── ThemeData ────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
      surface: surface,
      error: error,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: textDark,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: textDark,
        letterSpacing: -0.3,
      ),
    ),

    fontFamily: 'Pretendard',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: textDark,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: textDark,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: textDark,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textDark,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: textDark,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: textBody,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: textMuted,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 15),
        textStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ).copyWith(elevation: WidgetStateProperty.all(0)),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        color: textMuted,
      ),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
      margin: EdgeInsets.zero,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: textDark,
      contentTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 13,
        color: Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: textDark,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        color: textMuted,
        height: 1.6,
      ),
    ),
  );
}
