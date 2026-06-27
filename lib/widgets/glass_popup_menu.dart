import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_theme.dart';

class GlassMenuItem {
  final String value;
  final IconData icon;
  final String label;
  final bool destructive;

  const GlassMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
  });
}

/// 플로팅 툴바/앱바의 메뉴 버튼에 쓰는 glassmorphic 팝업 메뉴.
/// [openUpward]: true면 버튼 위로, false면 아래로 열림.
/// [alignRight]: true면 버튼 오른쪽 끝 기준 정렬.
class GlassPopupMenu extends StatefulWidget {
  final Widget child;
  final List<GlassMenuItem> items;
  final void Function(String) onSelected;
  final bool openUpward;
  final bool alignRight;
  final double? menuLeft;

  const GlassPopupMenu({
    super.key,
    required this.child,
    required this.items,
    required this.onSelected,
    this.openUpward = true,
    this.alignRight = false,
    this.menuLeft,
  });

  @override
  State<GlassPopupMenu> createState() => _GlassPopupMenuState();
}

class _GlassPopupMenuState extends State<GlassPopupMenu>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _entry;
  final _key = GlobalKey();
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _entry?.remove();
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final btnSize = box.size;
    final screen = MediaQuery.of(context).size;

    _entry = OverlayEntry(
      builder: (_) => _MenuOverlay(
        pos: pos,
        btnSize: btnSize,
        screenSize: screen,
        items: widget.items,
        openUpward: widget.openUpward,
        alignRight: widget.alignRight,
        menuLeft: widget.menuLeft,
        anim: _anim,
        onSelected: (v) {
          _close();
          widget.onSelected(v);
        },
        onDismiss: _close,
      ),
    );
    Overlay.of(context).insert(_entry!);
    _ctrl.forward(from: 0);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _key,
      behavior: HitTestBehavior.opaque,
      onTap: _entry == null ? _open : _close,
      child: widget.child,
    );
  }
}

class _MenuOverlay extends StatelessWidget {
  static const double _menuWidth = 200;
  static const double _itemHeight = 48;
  static const double _vPad = 8;
  static const double _gap = 10;

  final Offset pos;
  final Size btnSize;
  final Size screenSize;
  final List<GlassMenuItem> items;
  final bool openUpward;
  final bool alignRight;
  final double? menuLeft;
  final Animation<double> anim;
  final void Function(String) onSelected;
  final VoidCallback onDismiss;

  const _MenuOverlay({
    required this.pos,
    required this.btnSize,
    required this.screenSize,
    required this.items,
    required this.openUpward,
    required this.alignRight,
    this.menuLeft,
    required this.anim,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final menuH = items.length * _itemHeight + _vPad * 2;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final safeBottom = bottomInset + 106;

    double left;
    if (menuLeft != null) {
      left = menuLeft!;
    } else if (alignRight) {
      left = pos.dx + btnSize.width - _menuWidth;
    } else {
      left = pos.dx;
    }
    left = left.clamp(8.0, screenSize.width - _menuWidth - 8);

    double top = openUpward
        ? pos.dy - menuH - _gap
        : pos.dy + btnSize.height + _gap;
    top = top.clamp(8.0, screenSize.height - menuH - safeBottom);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: _menuWidth,
              child: AnimatedBuilder(
              animation: anim,
              builder: (_, child) => Opacity(
                opacity: anim.value,
                child: Transform.scale(
                  scale: 0.88 + 0.12 * anim.value,
                  alignment: _anchor(openUpward, alignRight),
                  child: child,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(vertical: _vPad),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items
                          .map((e) => _Item(item: e, onTap: () => onSelected(e.value)))
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Alignment _anchor(bool upward, bool right) {
    if (upward && right) return Alignment.bottomRight;
    if (upward) return Alignment.bottomLeft;
    if (right) return Alignment.topRight;
    return Alignment.topLeft;
  }
}

class _Item extends StatelessWidget {
  final GlassMenuItem item;
  final VoidCallback onTap;
  const _Item({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textColor = item.destructive ? AppTheme.error : AppTheme.textDark;
    final iconBg = item.destructive
        ? AppTheme.error.withValues(alpha: 0.08)
        : AppTheme.primaryBg;
    final iconColor = item.destructive ? AppTheme.error : AppTheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.black.withValues(alpha: 0.06),
        child: SizedBox(
          height: _MenuOverlay._itemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 10),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
