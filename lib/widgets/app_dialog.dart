import 'package:flutter/material.dart';
import '../app_theme.dart';

class DialogAction {
  final String label;
  final bool primary;
  final bool destructive;
  final VoidCallback onTap;

  const DialogAction({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.destructive = false,
  });
}

class AppDialog extends StatelessWidget {
  final String title;
  final String? content;
  final Widget? extra;
  final List<DialogAction> actions;
  final IconData? icon;

  const AppDialog({
    super.key,
    required this.title,
    required this.actions,
    this.content,
    this.extra,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hasDestructive = actions.any((a) => a.primary && a.destructive);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: hasDestructive
                        ? AppTheme.error.withValues(alpha: 0.10)
                        : AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon!,
                    size: 24,
                    color: hasDestructive ? AppTheme.error : AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            if (content != null) ...[
              const SizedBox(height: 10),
              Text(
                content!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.65,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (extra != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: extra!,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: actions.asMap().entries.map((entry) {
                final i = entry.key;
                final a = entry.value;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
                    child: a.primary
                        ? _PrimaryBtn(action: a)
                        : _SecondaryBtn(action: a),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final DialogAction action;
  const _PrimaryBtn({required this.action});

  @override
  Widget build(BuildContext context) {
    final colors = action.destructive
        ? [AppTheme.error, const Color(0xFFFF7070)]
        : [AppTheme.primary, AppTheme.gradientEnd];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              action.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class AppTextFieldDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final String confirmLabel;

  const AppTextFieldDialog({
    super.key,
    required this.title,
    required this.controller,
    required this.hintText,
    this.icon = Icons.edit_outlined,
    this.maxLength = 30,
    this.confirmLabel = '저장',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: maxLength,
              decoration: InputDecoration(
                hintText: hintText,
                counterText: '',
                filled: true,
                fillColor: AppTheme.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _SecondaryBtn(action: DialogAction(label: '취소', onTap: () => Navigator.pop(context)))),
                const SizedBox(width: 8),
                Expanded(child: _PrimaryBtn(action: DialogAction(label: confirmLabel, primary: true, onTap: () => Navigator.pop(context, controller.text)))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryBtn extends StatelessWidget {
  final DialogAction action;
  const _SecondaryBtn({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            action.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
