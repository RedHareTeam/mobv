import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MobvWordmark extends StatelessWidget {
  final double height;

  const MobvWordmark({super.key, this.height = 28});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/mobv-wordmark.png',
      height: height,
      fit: BoxFit.contain,
    );
  }
}

class MobvSymbol extends StatelessWidget {
  final double size;

  const MobvSymbol({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/mobv-symbol.svg',
      height: size,
      width: size * 172 / 116,
      fit: BoxFit.contain,
    );
  }
}
