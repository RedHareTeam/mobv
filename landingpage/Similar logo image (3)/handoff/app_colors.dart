import 'package:flutter/material.dart';

/// Mobv 브랜드 컬러 토큰
/// "모두가 괜찮은 곳에서 만나요 — Where everyone meets."
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF5865F2); // Indigo · 신뢰감 / 전문성
  static const Color secondary = Color(0xFF5AD6C0); // Mint · 친근함 / 활기
  static const Color accent = Color(0xFF2E9BC8); // Teal · 합의 / 공통 영역 (교집합)

  // Text
  static const Color textTitle = Color(0xFF1C2350); // 워드마크 / 헤드라인
  static const Color textBody = Color(0xFF3A4170); // 본문
  static const Color textMuted = Color(0xFF9AA0BD); // 보조 / 캡션

  // Surface
  static const Color background = Color(0xFFF4F5F8); // 앱 배경
  static const Color surface = Color(0xFFFFFFFF); // 카드 / 시트
  static const Color border = Color(0xFFE6E8F0); // 보더 / 구분선

  // State
  static const Color success = Color(0xFF2BB673);
  static const Color error = Color(0xFFE5484D);
}
