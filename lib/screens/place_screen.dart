import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../app_config.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/vote_service.dart';
import '../services/circle_service.dart';
import '../services/room_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/glassmorphic_container.dart';
import '../widgets/platform_html_view.dart';
import 'package:mobv/app_theme.dart';
import 'map_screen.dart';

/// 장소 추천 & 투표 화면
/// - 모든 멤버가 투표 완료 → 최다 득표 장소 자동 확정 → 확정 팝업
/// - 다시 그리기: places·votes만 초기화, status → 'drawing' (지도로 돌아감)
/// - 다시 만들기: 날짜·원·장소 모두 초기화, status → 'idle' (RoomHome으로 돌아감)
/// - 확인 버튼: confirmAndReset 호출 후 RoomHomeScreen까지 popUntil
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
  final _roomService = RoomService();

  late final TabController _tabController;

  List<Map<String, dynamic>> _votes = [];
  List<Map<String, dynamic>> _circles = [];
  String? _mySelectedId;
  StreamSubscription? _voteSub;
  StreamSubscription? _roomSub;

  bool _isNavigating = false;
  bool _confirmedShown = false;
  bool _confirmDialogOpen = false;
  bool _isConfirming = false;
  bool _tieDetected = false;

  static const _circleColors = [
    '#9D8EFF',
    '#FF9BDE',
    '#34D399',
    '#FBBF24',
    '#60A5FA',
  ];

  double _expansion = 1.0;

  static double _radiusExpansion(int score) {
    if (score <= 40) return 1.0;
    if (score <= 70) return 1.3;
    return 1.5;
  }

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
    _watchRoom();
  }

  Future<void> _loadCircles() async {
    final results = await Future.wait([
      _circleService.getAllCircles(widget.roomId),
      _roomService.getRoom(widget.roomId),
    ]);
    final raw = results[0] as List<Map<String, dynamic>>;
    final roomData = results[1] as Map<String, dynamic>?;
    final score = (roomData?['intimacyScore'] as num?)?.toInt() ?? 50;
    final expansion = _radiusExpansion(score);

    final colored = raw
        .asMap()
        .entries
        .map(
          (e) => {
            ...e.value,
            'radius': ((e.value['radius'] as num?) ?? 0) * expansion,
            'color': _circleColors[e.key % _circleColors.length],
          },
        )
        .toList();
    if (mounted)
      setState(() {
        _circles = colored;
        _expansion = expansion;
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _voteSub?.cancel();
    _roomSub?.cancel();
    super.dispose();
  }

  // ── Firestore 구독 ───────────────────────────────────────

  /// 방 상태 실시간 감지
  /// - 'drawing'  → 다시 그리기 완료: 이 화면(PlaceScreen)만 pop → MapScreen으로 복귀
  /// - 'idle'     → 다시 만들기 완료: RoomHomeScreen까지 popUntil
  /// - 'confirmed' → 장소 확정 팝업 표시
  void _watchRoom() {
    _roomSub = _roomService.watchRoom(widget.roomId).listen((room) {
      if (room == null || _isNavigating || !mounted) return;
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

      if (status == 'idle') {
        // 다시 만들기 → RoomHomeScreen까지
        _isNavigating = true;
        Navigator.pop(context);
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
        .collection('rooms')
        .doc(widget.roomId)
        .update({
          'places': [],
          'status': 'drawing',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// 다시 만들기
  /// 날짜·원·장소 모두 초기화, status → 'idle'
  Future<void> _resetAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '다시 만들기',
        content: '날짜, 원, 장소를 모두 초기화하고\n처음부터 다시 시작할까요?',
        icon: Icons.refresh_rounded,
        actions: [
          DialogAction(label: '취소', onTap: () => Navigator.pop(context, false)),
          DialogAction(
            label: '초기화',
            primary: true,
            destructive: true,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .update({
          'status': 'idle',
          'places': [],
          'appointmentDate': FieldValue.delete(),
          'confirmedPlace': FieldValue.delete(),
        });
    await _roomService.deleteSubcollection(widget.roomId, 'circles');
    await _roomService.deleteSubcollection(widget.roomId, 'votes');
    await _roomService.deleteSubcollection(widget.roomId, 'messages');
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
  /// 확인 버튼 → confirmAndReset 호출 → RoomHomeScreen으로 popUntil
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
            Navigator.of(context).pop(); // PlaceScreen → RoomHome
          }
          _cleanupConfirmedSession(); // 이전 세션 데이터 정리
        },
      ),
    ).then((_) => _confirmDialogOpen = false);
  }

  /// 확정 후 세션 데이터 정리 (circles/votes/messages 삭제 + status 초기화)
  /// 서브컬렉션을 먼저 삭제한 뒤 status 변경 → 새 세션이 이전 votes를 보는 race condition 방지
  Future<void> _cleanupConfirmedSession() async {
    for (final col in ['votes', 'circles', 'messages']) {
      await _roomService.deleteSubcollection(widget.roomId, col);
    }
    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .update({
          'status': 'waiting',
          'places': FieldValue.delete(),
          'confirmedPlace': FieldValue.delete(),
          'appointmentDate': FieldValue.delete(),
        });
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
      appBar: AppBar(
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
        title: const Text(
          '장소 선택',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          // 투표 현황 pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: voteRatio == 1.0
                  ? AppTheme.confirmed.withValues(alpha: 0.12)
                  : AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.how_to_vote_outlined,
                  size: 13,
                  color: voteRatio == 1.0
                      ? AppTheme.confirmed
                      : AppTheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  '$votedCount/${widget.members.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: voteRatio == 1.0
                        ? AppTheme.confirmed
                        : AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          GlassPopupMenu(
            openUpward: false,
            alignRight: true,
            onSelected: (v) {
              if (v == 'redraw') _resetAndRedraw();
              if (v == 'restart') _resetAll();
            },
            items: const [
              GlassMenuItem(
                value: 'redraw',
                icon: Icons.refresh_rounded,
                label: '다시 그리기',
              ),
              GlassMenuItem(
                value: 'restart',
                icon: Icons.replay_rounded,
                label: '다시 만들기',
                destructive: true,
              ),
            ],
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.more_vert_rounded,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
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
                    final voterNames = _votes
                        .where((v) => v['selectedPlaceId'] == placeId)
                        .map((v) => (v['userName'] as String?) ?? '')
                        .where((n) => n.isNotEmpty)
                        .toList();
                    final url = (place['url'] ?? place['kakaoUrl']) as String?;
                    return _PlaceCard(
                      place: place,
                      placeId: placeId,
                      rank: index + 1,
                      isSelected: isSelected,
                      voterNames: voterNames,
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
                    : Stack(
                        children: [
                          _PlaceMapView(
                            kakaoApiKey: AppConfig.kakaoJsKey,
                            circles: _circles,
                            places: widget.places,
                          ),
                          if (_expansion > 1.0)
                            Positioned(
                              top: 12,
                              left: 12,
                              child: GlassmorphicContainer(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                sigmaX: 8,
                                sigmaY: 8,
                                backgroundAlpha: 0.88,
                                baseColor: AppTheme.primary,
                                child: Text(
                                  '친밀도로 탐색 범위 ${(_expansion * 100).toInt()}% 확장',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
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

class _PlaceCard extends StatelessWidget {
  final Map<String, dynamic> place;
  final String placeId;
  final int rank;
  final bool isSelected;
  final List<String> voterNames;
  final VoidCallback onSelect;
  final VoidCallback? onDetail;

  const _PlaceCard({
    required this.place,
    required this.placeId,
    required this.rank,
    required this.isSelected,
    required this.voterNames,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
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
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isSelected ? '✓ 선택됨' : '선택',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // 투표자 닉네임
            if (voterNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1, color: AppTheme.border),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: voterNames
                    .map(
                      (name) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
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
