import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Mobv 로고 위젯
///
/// 에셋 등록 (pubspec.yaml):
///   flutter:
///     assets:
///       - assets/brand/mobv-wordmark.png
///       - assets/brand/mobv-symbol.svg
///   dependencies:
///     flutter_svg: ^2.0.0
///
/// 워드마크는 커스텀 글자 형태라 투명 PNG로 제공합니다.
/// 심볼(두 원)은 벡터 SVG라 어떤 크기에서도 선명합니다.

/// 가로형 워드마크 — 앱바 / 스플래시 / 헤더용
class MobvWordmark extends StatelessWidget {
  final double height;
  const MobvWordmark({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/mobv-wordmark.png',
      height: height, // 가로폭은 비율(약 3.2:1)에 맞춰 자동
      fit: BoxFit.contain,
    );
  }
}

/// 심볼 마크 — 아이콘 / 로딩 / 포인트용 (벡터)
class MobvSymbol extends StatelessWidget {
  final double size; // 높이(px) 기준
  const MobvSymbol({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/mobv-symbol.svg',
      height: size,
      width: size * 172 / 116, // 심볼 종횡비
    );
  }
}
