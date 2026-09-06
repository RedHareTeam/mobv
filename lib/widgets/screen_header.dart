import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';

class ScreenHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  const ScreenHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          color: AppTheme.textDark,
          onPressed: onBack ?? () => Navigator.pop(context),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
              letterSpacing: -0.3,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
