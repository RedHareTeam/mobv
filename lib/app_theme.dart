import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand (Minimal Monochrome) ────────────────────────────────
  static const primary = Color(0xFF18181B); // Deep Obsidian / Charcoal
  static const primaryBg = Color(0xFFF4F4F5); // Soft Light Gray

  static const secondary = Color(0xFF27272A);
  static const secondaryBg = Color(0xFFF4F4F5);

  static const accent = Color(0xFF09090B);
  static const accentBg = Color(0xFFF4F4F5);

  // ── Neutral ──────────────────────────────────────────────────
  static const bg = Color(0xFFFAFAFA); // Clean Off-White
  static const surface = Colors.white;
  static const textDark = Color(0xFF09090B); // Crisp Black
  static const textBody = Color(0xFF3F3F46); // Readable Dark Gray
  static const textMuted = Color(0xFF71717A); // Refined Gray
  static const border = Color(0xFFE4E4E7); // Subtle 1px Border

  // ── 상태별 색상 ──────────────────────────────────────────────
  static const drawing = primary;
  static const voting = secondary;
  static const confirmed = Color(0xFF16A34A); // Clean Emerald

  // ── 비활성 ───────────────────────────────────────────────────
  static const disabled = Color(0xFFA1A1AA);
  static const disabledBg = Color(0xFFF4F4F5);

  // ── 에러·경고 ────────────────────────────────────────────────
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const warningDark = Color(0xFFB45309);

  // ── 단색 통일 (그라데이션 제거) ──────────────────────────────
  static const gradientEnd = primary;
  static const cardGradientStart = surface;
  static const cardGradientEnd = surface;

  // ── 히트맵 밀도 색상 ────────────────────────────────────────
  static const heatmapLow = Color(0xFFCBD5E1);
  static const heatmapMid = Color(0xFF64748B);
  static const heatmapHigh = Color(0xFF0F172A);

  // ── ThemeData ────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
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
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: disabled,
        elevation: 0,
        shadowColor: Colors.transparent,
        side: const BorderSide(color: border, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
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
