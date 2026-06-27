import 'package:flutter/material.dart';

class AppTheme {
  // ── Primary — 웜 바이올렛 ────────────────────────────────────
  static const primary = Color.fromARGB(255, 255, 155, 222);
  static const primaryBg = Color.fromARGB(255, 255, 245, 255);

  // ── Accent — 코랄 로즈 ──────────────────────────────────────
  static const accent = Color(0xFFFF5F7E);
  static const accentBg = Color(0xFFFFEEF2);

  // ── Neutral ──────────────────────────────────────────────────
  static const bg = Color(0xFFF8F8FA);
  static const surface = Colors.white;
  static const textDark = Color(0xFF1C1C2E);
  static const textMuted = Color(0xFF9898AA);
  static const border = Color(0xFFEDEDF5);

  // ── 상태별 색상 ──────────────────────────────────────────────
  static const drawing = Color.fromARGB(255, 157, 142, 255); // 페리윙클
  static const voting = Color(0xFFFFA040); // 웜 앰버
  static const confirmed = Color(0xFF34D399); // 소프트 에메랄드

  // ── 비활성 ───────────────────────────────────────────────────
  static const disabled = Color(0xFFB8B4CC);
  static const disabledBg = Color(0xFFF2F0FA);

  // ── 에러·경고 ────────────────────────────────────────────────
  static const error = Color(0xFFFF4D67);
  static const warning = Color(0xFFFFBB00);
  static const warningDark = Color(0xFFCC9000);

  // ── 그래디언트 끝 색상 ───────────────────────────────────────
  static const gradientEnd = Color(0xFFFF7BAC);

  // ── 카드 배경 그래디언트 ─────────────────────────────────────
  static const cardGradientStart = Color(0xFFFFF0FA); // 연분홍
  static const cardGradientEnd   = Color(0xFFF0EEFF); // 연보라

  // ── 친밀도 단계별 색상 ────────────────────────────────────────
  static const intimacyTop = Color(0xFFFF9BDE); // 핑크    — 매우 친밀 (80+)
  static const intimacyHigh = Color.fromARGB(
    255,
    67,
    223,
    192,
  ); // 민트    — 꽤 가까운 사이 (60~79)
  static const intimacyMid = Color(0xFF9D8EFF); // 페리윙클 — 친해지는 중 (40~59)
  static const intimacyLow = Color(0xFFFFCC55); // 노랑    — 아직 서먹서먹 (~39)

  // ── ThemeData ────────────────────────────────────────────────
  static ThemeData get theme => ThemeData(
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: accent,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: -0.3,
      ),
    ),

    fontFamily: 'Pretendard',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: Color(0xFF1C1C2E),
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: Color(0xFF1C1C2E),
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: Color(0xFF1C1C2E),
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1C1C2E),
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1C1C2E),
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: Color(0xFF1C1C2E),
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: Color(0xFF1C1C2E),
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: Color(0xFF9898AA),
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
        color: Color(0xFF9898AA),
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
      ).copyWith(
        elevation: WidgetStateProperty.all(0),
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
        borderSide: const BorderSide(color: Color(0xFFEDEDF5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEDEDF5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        color: Color(0xFF9898AA),
      ),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEDEDF5)),
      ),
      margin: EdgeInsets.zero,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1C1C2E),
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
        color: Color(0xFF1C1C2E),
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 14,
        color: Color(0xFF9898AA),
        height: 1.6,
      ),
    ),
  );
}
