import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/vote_service.dart';
import '../services/circle_service.dart';
import '../services/appointment_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/gradient_button.dart';
import '../widgets/platform_html_view.dart';
import 'package:mobv/app_theme.dart';
import 'map_screen.dart';

/// 장소 추천 & 투표 화면
/// - 모든 멤버가 투표 완료 → 최다 득표 장소 자동 확정 → 확정 팝업
/// - 다시 그리기: places·votes만 초기화, status → 'drawing' (지도로 돌아감)
/// - 나가기: 약속을 삭제하고 홈으로 돌아감
/// - 확인 버튼: 확정된 약속 정보를 유지하고 홈으로 돌아감
class PlaceScreen extends StatefulWidget {
  final String roomId;
  final String userId;
  final String userName;
  final List<String> members;
  final List<Map<String, dynamic>> places;
  final DateTime? appointmentDate;

  const PlaceScreen({
    super.key,
    required this.roomId,
    required this.userId,
    required this.userName,
    required this.members,
    required this.places,
    this.appointmentDate,
  });

  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen>
    with SingleTickerProviderStateMixin {
  final _voteService = VoteService();
  final _circleService = CircleService();
  final _roomService = AppointmentService();

  late final TabController _tabController;

  List<Map<String, dynamic>> _votes = [];
  List<Map<String, dynamic>> _circles = [];
  Map<String, dynamic>? _appointmentData;
  String? _mySelectedId;
  StreamSubscription? _voteSub;
  StreamSubscription? _roomSub;

  bool _isNavigating = false;
  bool _confirmedShown = false;
  bool _confirmDialogOpen = false;
  bool _isConfirming = false;
  bool _tieDetected = false;

  // ── 생명주기 ────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    _loadCircles();
    _voteSub = _voteService.watchVotes(widget.roomId).listen((votes) {
      final myVote = votes.firstWhere(
        (v) => v['userId'] == widget.userId,
        orElse: () => {},
      );
      setState(() {
        _votes = votes;
        _mySelectedId = myVote['selectedPlaceId'] as String?;
      });
      // 투표가 비워지면 플래그 초기화 (동점 후 재투표 대비)
      if (votes.isEmpty) {
        _isConfirming = false;
        _tieDetected = false;
      }
      _checkAllVoted(votes);
    });
    _watchAppointment();
  }

  Future<void> _loadCircles() async {
    final results = await Future.wait([
      _circleService.getAllCircles(widget.roomId),
      _roomService.getAppointment(widget.roomId),
    ]);
    final raw = results[0] as List<Map<String, dynamic>>;
    final roomData = results[1] as Map<String, dynamic>?;
    _appointmentData = roomData;

    final colored = raw
        .asMap()
        .entries
        .map(
          (e) => {
            ...e.value,
            'radius': ((e.value['radius'] as num?) ?? 0).toDouble(),
            'color': _memberColorHex(
              roomData,
              e.value['userId']?.toString() ?? '',
            ),
          },
        )
        .toList();
    if (mounted) {
      setState(() {
        _circles = colored;
      });
    }
  }

  String _memberColorHex(Map<String, dynamic>? roomData, String userId) {
    final memberProfiles = Map<String, dynamic>.from(
      roomData?['memberProfiles'] as Map? ?? {},
    );
    final profile = Map<String, dynamic>.from(
      memberProfiles[userId] as Map? ?? {},
    );
    final legacyColors = Map<String, dynamic>.from(
      roomData?['memberColors'] as Map? ?? {},
    );
    final stored = profile['color'] ?? legacyColors[userId];
    final colorValue =
        _parseColorValue(stored) ?? _fallbackProfileColor(userId);
    return _colorValueToHex(colorValue);
  }

  int? _parseColorValue(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) {
      final normalized = value
          .trim()
          .replaceFirst('#', '')
          .replaceFirst('0x', '');
      return int.tryParse(normalized, radix: 16);
    }
    return null;
  }

  int _fallbackProfileColor(String userId) {
    if (userId.isEmpty) return AuthService.profileColorValues.first;
    final hash = userId.codeUnits.fold<int>(0, (total, code) => total + code);
    return AuthService.profileColorValues[hash %
        AuthService.profileColorValues.length];
  }

  String _colorValueToHex(int value) {
    final rgb = value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color _colorFromHex(String hex) {
    final rgb = hex.replaceFirst('#', '');
    return Color(int.parse('FF$rgb', radix: 16));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _voteSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  // ── Firestore 구독 ───────────────────────────────────────

  /// 약속 상태 실시간 감지
  /// - 'drawing'  → 다시 그리기 완료: 이 화면(PlaceScreen)만 pop → MapScreen으로 복귀
  /// - 'confirmed' → 장소 확정 팝업 표시
  void _watchAppointment() {
    _roomSub = _roomService.watchAppointment(widget.roomId).listen((room) {
      if (_isNavigating || !mounted) return;
      if (room == null) {
        _isNavigating = true;
        if (_confirmDialogOpen) Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('약속이 삭제되어 홈으로 돌아갑니다')));
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      _appointmentData = room;
      final status = room['status'] as String? ?? '';

      if (status == 'drawing') {
        _isNavigating = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MapScreen(
              roomId: widget.roomId,
              myUserId: widget.userId,
              myUserName: widget.userName,
              members: widget.members,
            ),
          ),
        );
        return;
      }

      if (status == 'waiting') {
        _isNavigating = true;
        if (_confirmedShown) {
          // 확정 후 초기화된 경우 → 조용히 홈으로
          if (mounted) {
            if (_confirmDialogOpen) Navigator.of(context).pop(); // 팝업 닫기
            Navigator.of(context).pop(); // PlaceScreen 나가기
          }
        } else {
          // 실제로 멤버가 나간 경우
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('멤버가 나가 처음으로 돌아갑니다')));
            Navigator.pop(context);
          }
        }
        return;
      }

      if (status == 'confirmed' && !_confirmedShown) {
        _confirmedShown = true;
        final confirmed = Map<String, dynamic>.from(
          room['confirmedPlace'] as Map? ?? {},
        );
        final members = List<String>.from(room['members'] ?? []);
        _showConfirmedDialog(confirmed, members);
      }
    });
  }

  // ── 투표 로직 ────────────────────────────────────────────

  /// 모든 멤버가 투표했으면 최다 득표 장소 확정
  Future<void> _checkAllVoted(List<Map<String, dynamic>> votes) async {
    if (_isConfirming || _tieDetected) return;
    if (votes.length < widget.members.length) return;
    final allSelected = votes.every((v) => v['selectedPlaceId'] != null);
    if (!allSelected) return;

    // 현재 places에 없는 placeId는 이전 세션 잔여 vote → 무시
    final validPlaceIds = widget.places
        .map((p) => p['kakaoId'] as String? ?? '')
        .toSet();
    final validVotes = votes.where((v) {
      final id = v['selectedPlaceId'] as String?;
      return id != null && validPlaceIds.contains(id);
    }).toList();
    if (validVotes.length < widget.members.length) return;

    final Map<String, int> tally = {};
    for (final v in validVotes) {
      final id = v['selectedPlaceId'] as String;
      tally[id] = (tally[id] ?? 0) + 1;
    }

    final maxVotes = tally.values.reduce((a, b) => a > b ? a : b);
    final topEntries = tally.entries.where((e) => e.value == maxVotes).toList();

    // 동점 처리
    if (topEntries.length > 1) {
      _tieDetected = true;
      if (mounted) _showTieDialog();
      return;
    }

    _isConfirming = true;
    final topId = topEntries.first.key;
    final confirmedList = widget.places
        .where((p) => (p['kakaoId'] ?? '') == topId)
        .toList();
    if (confirmedList.isEmpty) {
      // 투표 ID와 장소 데이터 불일치 — 투표 재시도
      _isConfirming = false;
      debugPrint('투표 결과 매핑 오류: topId=$topId');
      return;
    }
    final confirmed = confirmedList.first;
    // confirmPlace 먼저 → status 'confirmed'로 변경
    // saveConfirmHistory는 그 다음 → 트랜잭션 충돌 방지
    await _circleService.confirmPlace(widget.roomId, confirmed);
    await _roomService.saveConfirmHistory(
      roomId: widget.roomId,
      confirmedPlace: confirmed,
      members: widget.members,
      appointmentDate: widget.appointmentDate,
    );
    await _roomService.cleanupConfirmedAppointment(widget.roomId);
  }

  Future<void> _selectPlace(String placeId) async {
    if (_mySelectedId == placeId) {
      setState(() => _mySelectedId = null);
      await _voteService.clearVote(
        roomId: widget.roomId,
        userId: widget.userId,
      );
    } else {
      setState(() => _mySelectedId = placeId);
      await _voteService.selectPlace(
        roomId: widget.roomId,
        userId: widget.userId,
        userName: widget.userName,
        placeId: placeId,
      );
    }
  }

  // ── 메뉴 액션 ────────────────────────────────────────────

  /// 다시 그리기
  /// places·votes만 지우고 status → 'drawing'
  /// (_watchRoom이 'drawing'을 감지해 자동으로 이 화면을 pop)
  Future<void> _resetAndRedraw() async {
    // 서브컬렉션을 먼저 삭제한 뒤 status를 변경해야
    // _watchRoom이 'drawing'을 감지해 MapScreen으로 넘어갈 때 데이터가 깨끗함
    await _roomService.deleteSubcollection(widget.roomId, 'votes');
    await _roomService.deleteSubcollection(widget.roomId, 'circles');
    await FirebaseFirestore.instance
        .collection('appointments')
        .doc(widget.roomId)
        .update({
          'places': [],
          'status': 'drawing',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 나가기
  /// 약속을 삭제하고 홈으로 돌아감
  Future<void> _deleteAndExit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '약속에서 나갈까요?',
        content: '이 약속이 삭제되고 홈 화면으로 돌아가요.',
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
    if (confirm != true) return;

    _isNavigating = true;
    await _roomService.deleteAppointment(widget.roomId);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── 동점 팝업 ────────────────────────────────────────────

  void _showTieDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppDialog(
        title: '동점이에요',
        content: '득표수가 같아 장소를 확정할 수 없어요.\n다시 그리기를 하거나\n투표를 다시 진행해주세요.',
        icon: Icons.balance_outlined,
        actions: [
          DialogAction(
            label: '다시 투표',
            onTap: () {
              Navigator.pop(context);
              setState(() {
                _tieDetected = false;
                _mySelectedId = null;
              });
              _roomService.deleteSubcollection(widget.roomId, 'votes');
            },
          ),
          DialogAction(
            label: '다시 그리기',
            primary: true,
            onTap: () {
              Navigator.pop(context);
              _resetAndRedraw();
            },
          ),
        ],
      ),
    );
  }

  // ── 확정 팝업 ────────────────────────────────────────────

  /// 장소 확정 다이얼로그 표시
  /// 확인 버튼 → 확정 상태를 유지하고 홈으로 돌아감
  void _showConfirmedDialog(Map<String, dynamic> place, List<String> members) {
    if (!mounted) return;
    _confirmDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ConfirmedDialog(
        place: place,
        onConfirm: () {
          _isNavigating = true;
          _confirmDialogOpen = false;
          if (mounted) {
            Navigator.of(context).pop(); // 팝업 닫기
            Navigator.of(context).pop(); // PlaceScreen → Home
          }
        },
      ),
    ).then((_) => _confirmDialogOpen = false);
  }

  // ── 빌드 ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final votedCount = _votes.where((v) => v['selectedPlaceId'] != null).length;
    final voteRatio = widget.members.isEmpty
        ? 0.0
        : votedCount / widget.members.length;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 20, 8),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppCircleIconButton(
                        icon: Icons.chevron_left_rounded,
                        size: 38,
                        iconSize: 22,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const Text(
                      '장소 선택',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _VoteStatusPill(
                            votedCount: votedCount,
                            memberCount: widget.members.length,
                            completed: voteRatio == 1.0,
                          ),
                          const SizedBox(width: 8),
                          _PlaceMenuButton(
                            onRedraw: _resetAndRedraw,
                            onExit: _deleteAndExit,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── 탭 바 (pill 스타일) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.border),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '목록'),
                  Tab(text: '지도'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textMuted,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(20),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                padding: const EdgeInsets.all(3),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── 탭 내용 ──
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // 목록 탭
                ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: widget.places.length,
                  itemBuilder: (context, index) {
                    final place = widget.places[index];
                    final placeId = place['kakaoId'] ?? '$index';
                    final isSelected = _mySelectedId == placeId;
                    final voters = _votes
                        .where((v) => v['selectedPlaceId'] == placeId)
                        .map(
                          (v) => _VoteChipData(
                            name: (v['userName'] as String?) ?? '',
                            color: _colorFromHex(
                              _memberColorHex(
                                _appointmentData,
                                v['userId']?.toString() ?? '',
                              ),
                            ),
                          ),
                        )
                        .where((v) => v.name.isNotEmpty)
                        .toList();
                    final url = (place['url'] ?? place['kakaoUrl']) as String?;
                    return _PlaceCard(
                      place: place,
                      placeId: placeId,
                      rank: index + 1,
                      isSelected: isSelected,
                      voters: voters,
                      onSelect: () => _selectPlace(placeId),
                      onDetail: url != null && url.isNotEmpty
                          ? () => launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.inAppBrowserView,
                            )
                          : null,
                    );
                  },
                ),

                // 지도 탭
                _circles.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      )
                    : _PlaceMapView(
                        kakaoApiKey: AppConfig.kakaoJsKey,
                        circles: _circles,
                        places: widget.places,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 장소 카드
// ════════════════════════════════════════════════════════════

class _VoteStatusPill extends StatelessWidget {
  final int votedCount;
  final int memberCount;
  final bool completed;

  const _VoteStatusPill({
    required this.votedCount,
    required this.memberCount,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final color = completed ? AppTheme.confirmed : AppTheme.primary;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.how_to_vote_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$votedCount/$memberCount',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceMenuButton extends StatelessWidget {
  final VoidCallback onRedraw;
  final VoidCallback onExit;

  const _PlaceMenuButton({required this.onRedraw, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return GlassPopupMenu(
      openUpward: false,
      alignRight: true,
      onSelected: (value) {
        if (value == 'redraw') onRedraw();
        if (value == 'exit') onExit();
      },
      items: const [
        GlassMenuItem(
          value: 'redraw',
          icon: Icons.refresh_rounded,
          label: '다시 그리기',
        ),
        GlassMenuItem(
          value: 'exit',
          icon: Icons.logout_rounded,
          label: '나가기',
          destructive: true,
        ),
      ],
      child: const _PlaceMenuCircleIcon(),
    );
  }
}

class _PlaceMenuCircleIcon extends StatelessWidget {
  const _PlaceMenuCircleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
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
      child: const Center(
        child: Icon(
          Icons.more_horiz_rounded,
          color: AppTheme.textDark,
          size: 20,
        ),
      ),
    );
  }
}

class _VoteChipData {
  final String name;
  final Color color;

  const _VoteChipData({required this.name, required this.color});
}

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final int rank;
  final bool isSelected;
  final List<_VoteChipData> voters;
  final VoidCallback onSelect;
  final VoidCallback? onDetail;

  const _PlaceCard({
    required this.place,
    required this.placeId,
    required this.rank,
    required this.isSelected,
    required this.voters,
    required this.onSelect,
    this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final category = (place['category'] as String?) ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.6)
              : AppTheme.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isSelected ? 16 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 번호 뱃지
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : AppTheme.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 장소 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place['name'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        place['address'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 우측 버튼 영역
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (onDetail != null)
                      GestureDetector(
                        onTap: onDetail,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.bg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.map_outlined,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: onSelect,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.primary,
                                    AppTheme.gradientEnd,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                )
                              : null,
                          color: isSelected ? null : AppTheme.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: isSelected ? Colors.white : AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 투표자 닉네임
            if (voters.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppTheme.border),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: voters
                    .map((voter) => _VoterChip(voter: voter))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoterChip extends StatelessWidget {
  final _VoteChipData voter;

  const _VoterChip({required this.voter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: voter.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: voter.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            voter.name,
            style: TextStyle(
              fontSize: 11,
              color: voter.color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 장소 확정 다이얼로그
// ════════════════════════════════════════════════════════════

class _ConfirmedDialog extends StatelessWidget {
  final Map<String, dynamic> place;
  final VoidCallback onConfirm;

  const _ConfirmedDialog({required this.place, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final name = place['name'] ?? '';
    final address = place['address'] ?? '';
    final category = place['category'] ?? '';

    return AppDialog(
      title: '약속 장소가 확정됐어요!',
      icon: Icons.celebration_outlined,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          if (category.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              category,
              style: const TextStyle(fontSize: 12, color: AppTheme.primary),
            ),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        DialogAction(label: '확인하고 홈으로', primary: true, onTap: onConfirm),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// 교집합 확인 지도
// ════════════════════════════════════════════════════════════

class _PlaceMapView extends StatefulWidget {
  final String kakaoApiKey;
  final List<Map<String, dynamic>>
  circles; // {lat, lng, radius, userName, color}
  final List<Map<String, dynamic>> places; // {name, lat, lng, ...}

  const _PlaceMapView({
    required this.kakaoApiKey,
    required this.circles,
    required this.places,
  });

  @override
  State<_PlaceMapView> createState() => _PlaceMapViewState();
}

class _PlaceMapViewState extends State<_PlaceMapView> {
  PlatformHtmlViewController? _ctrl;

  void _initMapData() {
    final circlesJson = jsonEncode(
      widget.circles
          .map(
            (c) => {
              'lat': c['lat'],
              'lng': c['lng'],
              'radius': c['radius'],
              'userName': c['userName'] ?? '',
              'color': c['color'] ?? '#9D8EFF',
            },
          )
          .toList(),
    );
    final placesJson = jsonEncode(
      widget.places
          .map(
            (p) => {'name': p['name'] ?? '', 'lat': p['lat'], 'lng': p['lng']},
          )
          .toList(),
    );
    final cEnc = Uri.encodeComponent(circlesJson);
    final pEnc = Uri.encodeComponent(placesJson);
    _ctrl?.runJavaScript(
      'initMapData(JSON.parse(decodeURIComponent("$cEnc")), JSON.parse(decodeURIComponent("$pEnc")))',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformHtmlView(
      html: _buildHtml(),
      webUrl: '/place_map_bridge.html?appkey=${widget.kakaoApiKey}',
      channels: {
        'MapReadyChannel': (_) => _initMapData(),
        'PlaceTappedChannel': (msg) {
          final idx = int.tryParse(msg) ?? 0;
          if (idx < widget.places.length && mounted) {
            final place = widget.places[idx];
            final url = (place['url'] ?? place['kakaoUrl']) as String?;
            if (url != null && url.isNotEmpty) {
              launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
            }
          }
        },
      },
      onCreated: (ctrl) => _ctrl = ctrl,
    );
  }

  String _buildHtml() =>
      '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=yes">
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&display=swap" rel="stylesheet">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; -webkit-tap-highlight-color:transparent; font-family:"Noto Sans KR",-apple-system,"Apple SD Gothic Neo",system-ui,sans-serif; }
    body { width:100vw; height:100vh; overflow:hidden; }
    #map { width:100%; height:100%; }
    /* 핀 래퍼: 원(30×30)만 flow에 포함, 레이블은 absolute로 위에 띄움 */
    .pm { position:relative; width:30px; height:30px; cursor:pointer; }
    .pm-num {
      width:30px; height:30px; border-radius:50%;
      background:#FF5F7E; color:#fff;
      display:flex; align-items:center; justify-content:center;
      font-weight:700; font-size:13px;
      box-shadow:0 2px 6px rgba(0,0,0,0.28);
      transition: transform 0.32s cubic-bezier(0.34,1.56,0.64,1);
      transform-origin: center;
    }
    .pm:active .pm-num {
      transform: scale(0.78);
      transition-duration: 0.06s;
      transition-timing-function: ease-in;
    }
    .pm-name {
      position:absolute; bottom:calc(100% + 4px); left:50%;
      transform:translateX(-50%);
      background:#fff; color:#1C1C2E;
      padding:3px 8px; border-radius:8px;
      font-size:11px;
      white-space:nowrap; max-width:110px;
      overflow:hidden; text-overflow:ellipsis;
      box-shadow:0 1px 4px rgba(0,0,0,0.14);
      pointer-events:none;
    }
    .cm {
      padding:3px 9px; border-radius:10px;
      font-size:11px; font-weight:600;
      color:#fff; white-space:nowrap;
      box-shadow:0 1px 4px rgba(0,0,0,0.18);
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=${widget.kakaoApiKey}"></script>
  <script>
    document.addEventListener('touchstart', function(){}, {passive:true});
    var map;
    kakao.maps.load(function() {
      map = new kakao.maps.Map(document.getElementById('map'), {
        center: new kakao.maps.LatLng(37.5665, 126.9780),
        level: 7
      });
      MapReadyChannel.postMessage('ready');
    });

    function initMapData(circles, places) {
      var bounds = new kakao.maps.LatLngBounds();

      // 원 + 이름 레이블
      circles.forEach(function(c) {
        new kakao.maps.Circle({
          map: map,
          center: new kakao.maps.LatLng(c.lat, c.lng),
          radius: c.radius,
          strokeWeight: 2,
          strokeColor: c.color,
          strokeOpacity: 0.9,
          fillColor: c.color,
          fillOpacity: 0.15
        });

        var label = document.createElement('div');
        label.className = 'cm';
        label.style.background = c.color;
        label.innerText = c.userName;
        new kakao.maps.CustomOverlay({
          map: map,
          position: new kakao.maps.LatLng(c.lat, c.lng),
          content: label,
          yAnchor: 0.5
        });

        var dLat = c.radius / 111000;
        var dLng = c.radius / (111000 * Math.cos(c.lat * Math.PI / 180));
        bounds.extend(new kakao.maps.LatLng(c.lat + dLat, c.lng + dLng));
        bounds.extend(new kakao.maps.LatLng(c.lat - dLat, c.lng - dLng));
      });

      // 장소 번호 마커
      places.forEach(function(p, i) {
        var wrap = document.createElement('div');
        wrap.className = 'pm';

        var name = document.createElement('div');
        name.className = 'pm-name';
        name.innerText = p.name;

        var num = document.createElement('div');
        num.className = 'pm-num';
        num.innerText = (i + 1) + '';

        wrap.appendChild(name); // absolute → 원 위에 띄워짐
        wrap.appendChild(num);  // 원 자체가 flow 기준

        (function(idx) {
          wrap.addEventListener('click', function() {
            PlaceTappedChannel.postMessage(idx + '');
          });
        })(i);

        new kakao.maps.CustomOverlay({
          map: map,
          position: new kakao.maps.LatLng(p.lat, p.lng),
          content: wrap,
          yAnchor: 0.5  // 원의 중심 = 좌표
        });

        bounds.extend(new kakao.maps.LatLng(p.lat, p.lng));
      });

      if (circles.length > 0 || places.length > 0) {
        map.setBounds(bounds, 60);
      }
    }
  </script>
</body>
</html>
''';
}
