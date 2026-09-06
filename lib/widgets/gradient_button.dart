import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double height;
  final double? width;
  final BorderRadius borderRadius;
  final bool enabled;
  final bool loading;

  const GradientButton({
    super.key,
    required this.child,
    this.onTap,
    this.height = 52,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.enabled = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF4F4F5),
          borderRadius: borderRadius,
          border: Border.all(color: AppTheme.border),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: AppTheme.textDark,
                    strokeWidth: 2,
                  ),
                )
              : child,
        ),
      ),
    );
  }
}

/// 헤더에 쓰는 38×38 원형 앞으로가기 버튼
class CircleForwardButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool enabled;
  final bool loading;

  const CircleForwardButton({
    super.key,
    this.onTap,
    this.enabled = true,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : AppTheme.disabled,
          borderRadius: BorderRadius.circular(14),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
      ),
    );
  }
}

class AppCircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool loading;
  final double size;
  final double iconSize;

  const AppCircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.enabled = true,
    this.loading = false,
    this.size = 52,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;

    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: active ? onTap : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: iconSize * 0.68,
                    height: iconSize * 0.68,
                    child: const CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    icon,
                    color: active ? AppTheme.textDark : AppTheme.textMuted,
                    size: iconSize,
                  ),
          ),
        ),
      ),
    );
  }
}
