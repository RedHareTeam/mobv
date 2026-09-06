import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';
import 'gradient_button.dart';

class NoIntersectionSheet extends StatelessWidget {
  final VoidCallback onExpandRadius;
  final VoidCallback onRedraw;

  const NoIntersectionSheet({
    super.key,
    required this.onExpandRadius,
    required this.onRedraw,
  });

  static Future<void> show({
    required BuildContext context,
    required VoidCallback onExpandRadius,
    required VoidCallback onRedraw,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NoIntersectionSheet(
        onExpandRadius: onExpandRadius,
        onRedraw: onRedraw,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 34),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 상단 드래그 핸들
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 아이콘 및 안내
          Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFE4E6), width: 1.5),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: Color(0xFFE11D48),
                size: 26,
              ),
            ),
          ),
          const SizedBox(height: 14),

          const Text(
            '서로 겹치는 장소가 부족해요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '멤버들의 이동 범위가 너무 좁거나 교집합이 작아서\n추천할 수 있는 장소가 2곳 미만이에요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // 추천 액션 1: 반경 20% 넓히기 (Primary)
          GradientButton(
            onTap: () {
              Navigator.pop(context);
              onExpandRadius();
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.zoom_out_map_rounded, color: AppTheme.textDark, size: 18),
                SizedBox(width: 8),
                Text(
                  '내 이동 범위 20% 넓히기 (추천)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 추천 액션 2: 직접 다시 그리기 (Secondary)
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              onRedraw();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: const Text(
              '지도에서 범위 직접 다시 그리기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
