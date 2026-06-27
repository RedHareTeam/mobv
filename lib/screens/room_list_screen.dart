import 'dart:async';
import 'package:mobv/screens/room_home_screen.dart';
import 'package:mobv/screens/upload_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import '../widgets/app_dialog.dart';
import '../widgets/glass_popup_menu.dart';
import '../widgets/glassmorphic_container.dart';
import 'package:mobv/app_theme.dart';
import 'auth_screen.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final _authService = AuthService();
  final _roomService = RoomService();
  final _codeController = TextEditingController();
  final _searchController = TextEditingController();
  Stream<List<Map<String, dynamic>>>? _roomStream;
  String get _myUserId => _authService.currentUser?.uid ?? '';
  String _myUserName = '';
  String _searchQuery = '';
  String _filter = '모든 방';
  bool _searchOpen = false;
  StreamSubscription? _userNameSub;

  @override
  void initState() {
    super.initState();
    _roomStream = _roomService.watchMyRooms(_myUserId);
    _userNameSub = _authService.watchUserInfo(_myUserId).listen((info) {
      if (mounted) setState(() => _myUserName = info?['userName'] ?? '');
    });
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _userNameSub?.cancel();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ignore: unused_element
  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    if (mounted) setState(() => _myUserName = info?['userName'] ?? '');
  }

  Future<void> _createRoom() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UploadScreen()),
    );
  }

  Future<void> _joinRoom() async {
    _codeController.clear();
    showDialog(
      context: context,
      builder: (_) =>
          _JoinDialog(controller: _codeController, onJoin: _handleJoinCode),
    );
  }

  Future<void> _handleJoinCode(String code) async {
    final result = await _roomService.joinRoom(
      inviteCode: code,
      myUserId: _myUserId,
      myUserName: _myUserName,
    );
    if (!mounted) return;
    if (result == 'FULL') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('방이 가득 찼어요')));
    } else if (result != null) {
      final room = await _roomService.getRoom(result);
      if (room != null && mounted) _enterRoom(result, room);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('유효하지 않은 코드예요')));
    }
  }

  void _enterRoom(String roomId, Map<String, dynamic> room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'RoomHomeScreen'),
        builder: (_) => RoomHomeScreen(
          roomId: roomId,
          myUserId: _myUserId,
          myUserName: _myUserName,
          maxMembers: room['maxMembers'] ?? 2,
          initialRoomData: room,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _changeNickname() async {
    final controller = TextEditingController(text: _myUserName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AppTextFieldDialog(
        title: '닉네임 변경',
        controller: controller,
        hintText: '새 닉네임을 입력하세요',
        maxLength: 12,
        confirmLabel: '변경',
      ),
    );
    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == _myUserName)
      return;
    final trimmed = newName.trim();
    final db = FirebaseFirestore.instance;

    // users 문서 업데이트
    await db.collection('users').doc(_myUserId).update({'userName': trimmed});

    // 내가 속한 모든 방의 memberNames + circles 업데이트
    final roomsSnap = await db
        .collection('rooms')
        .where('members', arrayContains: _myUserId)
        .get();

    final batch = db.batch();
    for (final roomDoc in roomsSnap.docs) {
      batch.update(roomDoc.reference, {'memberNames.$_myUserId': trimmed});

      final circleRef = roomDoc.reference.collection('circles').doc(_myUserId);
      final circleSnap = await circleRef.get();
      if (circleSnap.exists) {
        batch.update(circleRef, {'userName': trimmed});
      }
    }
    await batch.commit();

    if (mounted) setState(() => _myUserName = trimmed);
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> rooms) {
    var result = rooms;
    if (_filter == '지도') {
      result = result.where((r) => r['status'] == 'drawing').toList();
    } else if (_filter == '투표') {
      result = result.where((r) => r['status'] == 'voting').toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result.where((r) {
        final title = (r['roomTitle'] as String? ?? '').toLowerCase();
        final names = Map<String, dynamic>.from(
          r['memberNames'] ?? {},
        ).values.map((e) => e.toString().toLowerCase()).join(' ');
        return title.contains(_searchQuery) || names.contains(_searchQuery);
      }).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _roomStream,
            builder: (context, snap) {
              final allRooms = snap.data ?? [];
              final rooms = _applyFilters(allRooms);
              final isLoading = snap.connectionState == ConnectionState.waiting;

              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: AppTheme.bg,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    automaticallyImplyLeading: false,
                    centerTitle: false,
                    titleSpacing: 20,
                    title: const Text(
                      'Mobv',
                      style: TextStyle(
                        fontFamily: 'Pacifico',
                        fontSize: 26,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),

                  // 인사 + 닉네임
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '안녕하세요!',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 28,
                            child: Text(
                              _myUserName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textDark,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 검색바 (필터 위에, 펼쳐질 때만)
                  SliverToBoxAdapter(
                    child: AnimatedCrossFade(
                      duration: const Duration(milliseconds: 220),
                      crossFadeState: _searchOpen
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: GlassmorphicContainer(
                          borderRadius: BorderRadius.circular(16),
                          sigmaX: 10,
                          sigmaY: 10,
                          padding: EdgeInsets.zero,
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: '방 이름 또는 멤버 검색',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      secondChild: const SizedBox.shrink(),
                    ),
                  ),

                  // 필터 칩 + 검색 아이콘
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(
                        children: [
                          ...['모든 방', '지도', '투표'].map((label) {
                            final selected = _filter == label;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setState(() => _filter = label),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppTheme.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.border,
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.primary
                                                  .withValues(alpha: 0.28),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const Spacer(),
                          // 검색 아이콘
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _searchOpen
                                ? GestureDetector(
                                    key: const ValueKey('close'),
                                    onTap: () => setState(() {
                                      _searchOpen = false;
                                      _searchController.clear();
                                    }),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    key: const ValueKey('search'),
                                    onTap: () =>
                                        setState(() => _searchOpen = true),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.search_rounded,
                                        size: 18,
                                        color: AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 방 목록
                  if (isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary,
                        ),
                      ),
                    )
                  else if (rooms.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmpty(allRooms.isEmpty, botPad),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, botPad + 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _RoomCard(
                            room: rooms[i],
                            myUserId: _myUserId,
                            onTap: () =>
                                _enterRoom(rooms[i]['roomId'], rooms[i]),
                          ),
                          childCount: rooms.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // 하단 플로팅 툴바
          Positioned(
            bottom: botPad + 16,
            left: 16,
            right: 16,
            child: _FloatingToolbar(
              onSignOut: _signOut,
              onChangeNickname: _changeNickname,
              onCreateRoom: _createRoom,
              onJoinRoom: _joinRoom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool noRoomsAtAll, double botPad) {
    return Padding(
      padding: EdgeInsets.only(bottom: botPad + 66),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryBg, AppTheme.accentBg],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 32,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              noRoomsAtAll ? '아직 참여 중인 방이 없어요' : '해당하는 방이 없어요',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              noRoomsAtAll
                  ? '아래 버튼으로 새 방을 만들거나\n코드로 친구 방에 입장해보세요'
                  : '필터나 검색어를 바꿔보세요',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 하단 플로팅 툴바
// ════════════════════════════════════════════════════════════

class _FloatingToolbar extends StatelessWidget {
  final VoidCallback onSignOut;
  final VoidCallback onChangeNickname;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinRoom;

  const _FloatingToolbar({
    required this.onSignOut,
    required this.onChangeNickname,
    required this.onCreateRoom,
    required this.onJoinRoom,
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
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
          // 프로필/설정 버튼
          GlassPopupMenu(
            openUpward: true,
            alignRight: false,
            menuLeft: 16,
            onSelected: (v) {
              if (v == 'nickname') onChangeNickname();
              if (v == 'logout') onSignOut();
            },
            items: const [
              GlassMenuItem(
                value: 'nickname',
                icon: Icons.edit_outlined,
                label: '닉네임 변경',
              ),
              GlassMenuItem(
                value: 'logout',
                icon: Icons.logout_rounded,
                label: '로그아웃',
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
                Icons.person_outline_rounded,
                color: AppTheme.textMuted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 스플릿 FAB
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.gradientEnd],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  children: [
                    // 새 방 만들기
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onCreateRoom,
                          splashColor: Colors.white.withValues(alpha: 0.22),
                          highlightColor: Colors.white.withValues(alpha: 0.12),
                          child: SizedBox.expand(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.add_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '새 방',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 구분선
                    Container(
                      width: 1,
                      height: 26,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),

                    // 방 참여하기
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onJoinRoom,
                          splashColor: Colors.white.withValues(alpha: 0.22),
                          highlightColor: Colors.white.withValues(alpha: 0.12),
                          child: SizedBox.expand(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.vpn_key_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '참여',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 초대코드 다이얼로그
// ════════════════════════════════════════════════════════════

class _JoinDialog extends StatefulWidget {
  final TextEditingController controller;
  final Future<void> Function(String code) onJoin;

  const _JoinDialog({required this.controller, required this.onJoin});

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  bool _loading = false;

  Future<void> _submit() async {
    final code = widget.controller.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    Navigator.pop(context);
    await widget.onJoin(code);
  }

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '초대 코드 입력',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              '친구에게 받은 6자리 코드를 입력하세요',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: widget.controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                color: AppTheme.textDark,
              ),
              decoration: InputDecoration(
                hintText: '······',
                hintStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                  color: AppTheme.border,
                ),
                filled: true,
                fillColor: AppTheme.bg,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Center(
                          child: Text(
                            '취소',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.gradientEnd],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _loading ? null : _submit,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    '입장하기',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// 방 카드
// ════════════════════════════════════════════════════════════

class _RoomCard extends StatelessWidget {
  final Map<String, dynamic> room;
  final String myUserId;
  final VoidCallback onTap;

  const _RoomCard({
    required this.room,
    required this.myUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final roomTitle = room['roomTitle'] as String? ?? '제목 없음';
    final members = List<String>.from(room['members'] ?? []);
    final memberNames = Map<String, dynamic>.from(room['memberNames'] ?? {});
    final names = members
        .map((uid) => memberNames[uid]?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final status = room['status'] as String? ?? 'idle';
    final isActive = status == 'drawing' || status == 'voting';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? _statusColor(status).withValues(alpha: 0.3)
                : AppTheme.border,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? _statusColor(status).withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isActive
                      ? _statusColor(status).withValues(alpha: 0.15)
                      : AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    roomTitle.isNotEmpty ? roomTitle[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: isActive ? _statusColor(status) : AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      names.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isActive) ...[
                _StatusBadge(status: status),
                const SizedBox(width: 4),
              ] else
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.border,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) =>
      status == 'drawing' ? AppTheme.drawing : AppTheme.voting;
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDrawing = status == 'drawing';
    final color = isDrawing ? AppTheme.drawing : AppTheme.voting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            isDrawing ? '지도' : '투표',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
