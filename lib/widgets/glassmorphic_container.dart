import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double sigmaX;
  final double sigmaY;
  final double backgroundAlpha;
  final Color baseColor;
  final List<BoxShadow> boxShadow;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.sigmaX = 12,
    this.sigmaY = 12,
    this.backgroundAlpha = 0.82,
    this.baseColor = Colors.white,
    this.boxShadow = const [],
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: kIsWeb ? (backgroundAlpha + 0.1).clamp(0.0, 1.0) : backgroundAlpha),
        borderRadius: borderRadius,
        border: Border.all(color: baseColor.withValues(alpha: 0.6)),
      ),
      child: child,
    );

    final glassy = ClipRRect(
      borderRadius: borderRadius,
      child: kIsWeb
          ? inner
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
              child: inner,
            ),
    );

    if (boxShadow.isEmpty) return glassy;

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow),
      child: glassy,
    );
  }
}
