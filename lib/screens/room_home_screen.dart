import 'dart:async';
import 'package:mobv/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobv/screens/heatmap_screen.dart';
import 'package:mobv/screens/place_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/history_service.dart';
import '../services/room_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/glassmorphic_container.dart';
import 'package:url_launcher/url_launcher.dart';
import 'date_setting_screen.dart';
import 'map_screen.dart';

class RoomHomeScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final int maxMembers;
  final Map<String, dynamic>? initialRoomData;

  const RoomHomeScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.maxMembers,
    this.initialRoomData,
  });

  @override
  State<RoomHomeScreen> createState() => _RoomHomeScreenState();
}

class _RoomHomeScreenState extends State<RoomHomeScreen> {
  final _roomService = RoomService();
  final _historyService = HistoryService();

  List<Map<String, dynamic>> _schedules = [];
  StreamSubscription? _scheduleSub;
  Map<String, dynamic>? _roomData;
  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    _roomData = widget.initialRoomData;
    _watchRoom();
    _watchSchedules();
  }

  void _watchRoom() {
    _roomSub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null) return;
      setState(() {
        _roomData = room;
      });
    });
  }

  void _watchSchedules() {
    _scheduleSub = _historyService.watchHistory(widget.roomId).listen((
      history,
    ) {
      final now = DateTime.now();
      final upcoming = history.where((h) {
        final dateTs = h['appointmentDate'];
        if (dateTs == null) return false;
        final date = (dateTs as dynamic).toDate() as DateTime;
        return date.isAfter(now);
      }).toList();

      upcoming.sort((a, b) {
        final da = (a['appointmentDate'] as dynamic).toDate() as DateTime;
        final db = (b['appointmentDate'] as dynamic).toDate() as DateTime;
        return da.compareTo(db);
      });

      setState(() => _schedules = upcoming.cast<Map<String, dynamic>>());
    });
  }

  String _weekdayLabel(int wd) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[(wd - 1) % 7];
  }

  Future<void> _renameRoom() async {
    final currentTitle = _roomData?['roomTitle'] ?? '';
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => AppTextFieldDialog(
        title: '방 제목 수정',
        controller: controller,
        hintText: '방 제목을 입력하세요',
        maxLength: 30,
      ),
    );
    if (newTitle == null ||
        newTitle.trim().isEmpty ||
        newTitle.trim() == currentTitle)
      return;
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .update({'roomTitle': newTitle.trim()});
  }

  Future<void> _confirmLeave() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '방 나가기',
        content:
            '방을 나가면 다시 초대 코드로 입장해야 해요.\n지도/투표 진행 중이라면 내용이 초기화됩니다.\n\n정말 나가시겠어요?',
        icon: Icons.logout_rounded,
        actions: [
          DialogAction(label: '취소', onTap: () => Navigator.pop(context, false)),
          DialogAction(
            label: '나가기',
            primary: true,
            destructive: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _roomService.leaveRoom(
      roomId: widget.roomId,
      userId: widget.myUserId,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _scheduleSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  // ── 메인 액션 파라미터 ────────────────────────────────────
  _ActionParams _resolveAction() {
    final status = _roomData?['status'] ?? 'idle';
    final members = List<String>.from(_roomData?['members'] ?? []);
    final isFull = members.length >= widget.maxMembers;

    if (status == 'voting') {
      return _ActionParams(
        label: '장소 투표 참여하기',
        icon: Icons.how_to_vote_outlined,
        colors: [AppTheme.accent, const Color(0xFFFFAA88)],
        enabled: true,
        onTap: () {
          final places = List<Map<String, dynamic>>.from(
            _roomData?['places'] ?? [],
          );
          final dateTs = _roomData?['appointmentDate'];
          final appointmentDate = dateTs != null
              ? (dateTs as dynamic).toDate() as DateTime
              : null;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaceScreen(
                roomId: widget.roomId,
                userId: widget.myUserId,
                userName: widget.myUserName,
                members: members,
                places: places,
                appointmentDate: appointmentDate,
              ),
            ),
          );
        },
      );
    }

    if (status == 'drawing' && _roomData?['appointmentDate'] != null) {
      return _ActionParams(
        label: '지도 보러 가기',
        icon: Icons.map_outlined,
        colors: [AppTheme.drawing, const Color(0xFF7BB8FF)],
        enabled: true,
        onTap: () async {
          await Future.delayed(const Duration(milliseconds: 100));
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                roomId: widget.roomId,
                myUserId: widget.myUserId,
                myUserName: widget.myUserName,
                members: members,
              ),
            ),
          );
        },
      );
    }

    if (!isFull) {
      return _ActionParams(
        label: '${widget.maxMembers - members.length}명 더 참여해야 약속을 만들 수 있어요',
        icon: Icons.group_outlined,
        colors: [AppTheme.disabled, AppTheme.disabled],
        enabled: false,
        onTap: null,
      );
    }

    return _ActionParams(
      label: '약속 만들기',
      icon: Icons.add_circle_outline,
      colors: [AppTheme.primary, AppTheme.gradientEnd],
      enabled: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DateSettingScreen(
            roomId: widget.roomId,
            myUserId: widget.myUserId,
            myUserName: widget.myUserName,
            maxMembers: widget.maxMembers,
            members: members,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    final inviteCode = _roomData?['inviteCode'] ?? '';
    final currentMembers = List<String>.from(
      _roomData?['members'] ?? [widget.myUserId],
    );
    final memberNames = Map<String, dynamic>.from(
      _roomData?['memberNames'] ?? {},
    );
    final isFull = currentMembers.length >= widget.maxMembers;
    final action = _resolveAction();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppTheme.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                centerTitle: false,
                titleSpacing: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.chevron_left_rounded,
                    size: 28,
                    color: AppTheme.textDark,
                  ),
                  onPressed: () => Navigator.pop(context),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
                title: Text(
                  _roomData?['roomTitle'] ?? '',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  if (inviteCode.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('초대 코드 $inviteCode 복사됨')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.tag,
                                size: 13,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                inviteCode,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, botPad + 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── 멤버 현황 카드 ──
                    GlassmorphicContainer(
                      padding: const EdgeInsets.all(16),
                      backgroundAlpha: 0.75,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isFull
                                    ? Icons.group_rounded
                                    : Icons.group_outlined,
                                size: 18,
                                color: isFull
                                    ? AppTheme.primary
                                    : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isFull
                                    ? '${currentMembers.length}/${widget.maxMembers}명 모두 참여했어요!'
                                    : '${currentMembers.length}/${widget.maxMembers}명 참여 중 · 친구를 초대하세요',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isFull
                                      ? AppTheme.primary
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          if (currentMembers.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children:
                                  [
                                    widget.myUserId,
                                    ...currentMembers.where(
                                      (uid) => uid != widget.myUserId,
                                    ),
                                  ].map((uid) {
                                    final name =
                                        memberNames[uid] as String? ?? uid;
                                    final isMe = uid == widget.myUserId;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: isMe
                                            ? const LinearGradient(
                                                colors: [
                                                  AppTheme.primary,
                                                  AppTheme.gradientEnd,
                                                ],
                                              )
                                            : null,
                                        color: isMe ? null : AppTheme.bg,
                                        borderRadius: BorderRadius.circular(20),
                                        border: isMe
                                            ? null
                                            : Border.all(
                                                color: AppTheme.border,
                                              ),
                                      ),
                                      child: Text(
                                        isMe ? '$name (나)' : name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isMe
                                              ? Colors.white
                                              : AppTheme.textDark,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── 방문 히스토리 지도 ──
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HeatmapScreen(
                            roomId: widget.roomId,
                            myUserId: widget.myUserId,
                            myUserName: widget.myUserName,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.primary, Color(0xFF9B8BFF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.map_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '방문 히스토리 지도',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    '다녀온 장소를 지도로 확인해요',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.border,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── 다가오는 약속 ──
                    const Text(
                      '다가오는 약속',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_schedules.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 34,
                              color: AppTheme.border,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              '아직 약속이 없어요\n아래 버튼으로 첫 약속을 잡아보세요!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(_schedules.length, (i) {
                        final s = _schedules[i];
                        final place = Map<String, dynamic>.from(
                          s['confirmedPlace'] as Map? ?? {},
                        );
                        final date =
                            ((s['appointmentDate'] as dynamic).toDate()
                                    as DateTime)
                                .toLocal();
                        final isNext = i == 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isNext
                                  ? AppTheme.primary.withValues(alpha: 0.35)
                                  : AppTheme.border,
                              width: isNext ? 1.5 : 1,
                            ),
                            boxShadow: isNext
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.08,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: isNext
                                      ? const LinearGradient(
                                          colors: [
                                            AppTheme.primary,
                                            AppTheme.gradientEnd,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  color: isNext ? null : AppTheme.bg,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${date.month}/${date.day}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isNext
                                            ? Colors.white
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                    Text(
                                      _weekdayLabel(date.weekday),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isNext
                                            ? Colors.white70
                                            : AppTheme.disabled,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isNext)
                                      const Text(
                                        '가장 가까운 약속',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      place['name'] ?? '장소 미정',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                    Text(
                                      place['address'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if ((place['url'] ?? place['kakaoUrl'])
                                  case final String url
                                  when url.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => launchUrl(
                                    Uri.parse(url),
                                    mode: LaunchMode.inAppBrowserView,
                                  ),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isNext
                                          ? AppTheme.primary.withValues(
                                              alpha: 0.12,
                                            )
                                          : AppTheme.bg,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.map_outlined,
                                      size: 18,
                                      color: isNext
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                  ]),
                ),
              ),
            ],
          ),

          // ── 하단 플로팅 툴바 ──
          Positioned(
            bottom: botPad + 16,
            left: 16,
            right: 16,
            child: GlassmorphicContainer(
              borderRadius: BorderRadius.circular(28),
              sigmaX: 20,
              sigmaY: 20,
              backgroundAlpha: 0.72,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
              child: Row(
                children: [
                  // 더보기 메뉴
                  GlassPopupMenu(
                    openUpward: true,
                    alignRight: false,
                    menuLeft: 16,
                    onSelected: (v) {
                      if (v == 'rename') _renameRoom();
                      if (v == 'leave') _confirmLeave();
                    },
                    items: const [
                      GlassMenuItem(
                        value: 'rename',
                        icon: Icons.edit_outlined,
                        label: '방 제목 수정',
                      ),
                      GlassMenuItem(
                        value: 'leave',
                        icon: Icons.logout_rounded,
                        label: '방 나가기',
                        destructive: true,
                      ),
                    ],
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.more_horiz_rounded,
                        color: AppTheme.textMuted,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 메인 액션 버튼
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: action.enabled
                            ? LinearGradient(
                                colors: action.colors,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : null,
                        color: action.enabled ? null : AppTheme.disabledBg,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: action.enabled
                            ? [
                                BoxShadow(
                                  color: action.colors.first.withValues(
                                    alpha: 0.32,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: action.onTap,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  action.icon,
                                  color: action.enabled
                                      ? Colors.white
                                      : AppTheme.disabled,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    action.label,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: action.enabled
                                          ? Colors.white
                                          : AppTheme.disabled,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 액션 파라미터 데이터 클래스 ───────────────────────────────
class _ActionParams {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool enabled;
  final VoidCallback? onTap;

  const _ActionParams({
    required this.label,
    required this.icon,
    required this.colors,
    required this.enabled,
    required this.onTap,
  });
}
