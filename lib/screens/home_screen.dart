import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobv/app_theme.dart';
import 'package:mobv/screens/create_appointment_screen.dart';
import 'package:mobv/screens/map_screen.dart';
import 'package:mobv/screens/place_screen.dart';
import 'package:mobv/screens/date_coordination_screen.dart';
import 'package:mobv/services/auth_service.dart';
import 'package:mobv/services/appointment_service.dart';
import 'package:mobv/widgets/app_dialog.dart';
import 'package:mobv/widgets/glass_popup_menu.dart';
import 'package:mobv/widgets/gradient_button.dart';
import 'package:mobv/widgets/mobv_brand.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeSpacing {
  static const double pageX = 20;
  static const double headerTop = 22;
  static const double headerBottom = 10;
  static const double mapTop = 12;
  static const double sectionTop = 28;
  static const double sectionTitleBottom = 12;
  static const double cardGap = 12;
  static const double pageBottom = 28;

  static EdgeInsets header(double topPad) =>
      EdgeInsets.fromLTRB(pageX, topPad + headerTop, pageX, headerBottom);

  static const EdgeInsets mapCard = EdgeInsets.fromLTRB(
    pageX,
    mapTop,
    pageX,
    0,
  );

  static const EdgeInsets sectionTitle = EdgeInsets.fromLTRB(
    pageX,
    sectionTop,
    pageX,
    sectionTitleBottom,
  );

  static const EdgeInsets sectionContent = EdgeInsets.symmetric(
    horizontal: pageX,
  );

  static EdgeInsets bottomSectionContent(double bottomPad) =>
      EdgeInsets.fromLTRB(pageX, 0, pageX, bottomPad + pageBottom);
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _roomService = AppointmentService();
  final _codeController = TextEditingController();

  Stream<List<Map<String, dynamic>>>? _appointmentStream;
  StreamSubscription? _userSub;
  String get _myUserId => _authService.currentUser?.uid ?? '';
  String _myUserName = '';
  int _profileColorValue = AuthService.profileColorValues.first;
  bool _userInfoLoaded = false;

  @override
  void initState() {
    super.initState();
    _appointmentStream = _roomService.watchMyAppointments(_myUserId);
    _profileColorValue = _authService.fallbackProfileColor(_myUserId);
    _userSub = _authService.watchUserInfo(_myUserId).listen((info) {
      if (!mounted || info == null) return;
      setState(() {
        _myUserName = info['userName']?.toString() ?? '';
        _profileColorValue =
            (info['profileColor'] as num?)?.toInt() ??
            _authService.fallbackProfileColor(_myUserId);
        _userInfoLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createAppointment() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateAppointmentScreen()),
    );
  }

  Future<void> _joinByCode() async {
    _codeController.clear();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _JoinDialog(controller: _codeController),
    );
    if (code == null || code.isEmpty || !mounted) return;
    await _handleJoinCode(code);
  }

  Future<void> _handleJoinCode(String code) async {
    final result = await _roomService.joinAppointment(
      inviteCode: code,
      myUserId: _myUserId,
      myUserName: _myUserName,
      myProfileColor: _profileColorValue,
    );
    if (!mounted) return;
    if (result == 'FULL') {
      _showHomeSnack('참여 인원이 가득 찼어요');
    } else if (result == 'CLOSED') {
      _showHomeSnack('장소 선택이 시작된 약속은 새로 참여할 수 없어요');
    } else if (result != null) {
      final room = await _roomService.getAppointment(result);
      if (room != null && mounted) _enterAppointment(result, room);
    } else {
      _showHomeSnack('유효하지 않은 코드예요');
    }
  }

  void _showHomeSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _enterAppointment(String roomId, Map<String, dynamic> room) {
    final status = room['status']?.toString();
    final members = List<String>.from(room['members'] ?? []);
    final places = List<Map<String, dynamic>>.from(room['places'] ?? []);
    final confirmedPlace = Map<String, dynamic>.from(
      room['confirmedPlace'] as Map? ?? {},
    );
    final appointmentDate = _appointmentDateFrom(room['appointmentDate']);

    // 1. 날짜 조율 단계인 경우
    if (status == 'date_voting') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DateCoordinationScreen(
            roomId: roomId,
            myUserId: _myUserId,
            myUserName: _myUserName,
            myProfileColor: _profileColorValue,
            members: members,
          ),
        ),
      );
      return;
    }

    if (_shouldOpenPlaceScreen(status, places, confirmedPlace)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlaceScreen(
            roomId: roomId,
            userId: _myUserId,
            userName: _myUserName,
            members: members,
            places: places.isNotEmpty ? places : [confirmedPlace],
            appointmentDate: appointmentDate,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          roomId: roomId,
          myUserId: _myUserId,
          myUserName: _myUserName,
          members: members,
        ),
      ),
    );
  }

  bool _shouldOpenPlaceScreen(
    String? status,
    List<Map<String, dynamic>> places,
    Map<String, dynamic> confirmedPlace,
  ) {
    return status == 'voting' ||
        status == 'recommended' ||
        status == 'confirmed' ||
        places.isNotEmpty ||
        confirmedPlace.isNotEmpty;
  }

  DateTime? _appointmentDateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
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
        newName.trim() == _myUserName) {
      return;
    }

    final trimmed = newName.trim();
    final db = FirebaseFirestore.instance;
    await db.collection('users').doc(_myUserId).update({'userName': trimmed});

    final roomsSnap = await db
        .collection('appointments')
        .where('members', arrayContains: _myUserId)
        .get();
    final batch = db.batch();
    for (final roomDoc in roomsSnap.docs) {
      batch.update(roomDoc.reference, {
        'memberProfiles.$_myUserId.name': trimmed,
      });

      final circleRef = roomDoc.reference.collection('circles').doc(_myUserId);
      final circleSnap = await circleRef.get();
      if (circleSnap.exists) {
        batch.update(circleRef, {'userName': trimmed});
      }
    }
    await batch.commit();

    if (mounted) setState(() => _myUserName = trimmed);
  }

  Future<void> _changeProfileColor() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => _ColorPickerDialog(selectedColor: _profileColorValue),
    );
    if (selected == null || selected == _profileColorValue) return;
    await _authService.updateProfileColor(_myUserId, selected);
    if (mounted) setState(() => _profileColorValue = selected);
  }

  void _openMeetingMap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('우리의 만남 지도는 확정된 약속 기록을 모아서 연결할게요')),
    );
  }

  List<Map<String, dynamic>> _activeAppointments(
    List<Map<String, dynamic>> rooms,
  ) {
    return rooms.where((room) => !_isUpcoming(room)).toList();
  }

  List<Map<String, dynamic>> _upcomingAppointments(
    List<Map<String, dynamic>> rooms,
  ) {
    final upcoming = rooms.where(_isUpcoming).toList();
    upcoming.sort((a, b) {
      final aDate = _appointmentDateFrom(a['appointmentDate']);
      final bDate = _appointmentDateFrom(b['appointmentDate']);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return upcoming;
  }

  bool _isUpcoming(Map<String, dynamic> room) {
    final status = room['status']?.toString();
    final confirmedPlace = room['confirmedPlace'];
    return status == 'confirmed' ||
        (confirmedPlace is Map && confirmedPlace.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _appointmentStream,
        initialData: const [],
        builder: (context, snap) {
          final appointments = snap.data ?? [];
          final active = _activeAppointments(appointments);
          final upcoming = _upcomingAppointments(appointments);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: _HomeSpacing.header(topPad),
                  child: _HomeHeader(
                    profileColor: Color(_profileColorValue),
                    userName: _myUserName,
                    profileLoading: !_userInfoLoaded,
                    onCreate: _createAppointment,
                    onChangeNickname: _changeNickname,
                    onChangeColor: _changeProfileColor,
                    onJoinByCode: _joinByCode,
                    onSignOut: _signOut,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: _HomeSpacing.mapCard,
                  child: _MeetingMapCard(
                    appointmentCount: appointments.length,
                    onTap: _openMeetingMap,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: _HomeSpacing.sectionTitle,
                  child: _SectionTitle(title: '진행 중인 약속', count: active.length),
                ),
              ),
              if (active.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: _HomeSpacing.sectionContent,
                    child: _EmptyBlock(
                      title: '아직 진행 중인 약속이 없어요',
                      body: '+ 버튼으로 새 약속을 만들 수 있어요',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: _HomeSpacing.sectionContent,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _AppointmentCard(
                        appointment: active[index],
                        compact: false,
                        bottomMargin: index == active.length - 1
                            ? 0
                            : _HomeSpacing.cardGap,
                        onTap: () => _enterAppointment(
                          active[index]['roomId'],
                          active[index],
                        ),
                      ),
                      childCount: active.length,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: _HomeSpacing.sectionTitle,
                  child: _SectionTitle(
                    title: '다가오는 약속',
                    count: upcoming.length,
                  ),
                ),
              ),
              if (upcoming.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: _HomeSpacing.bottomSectionContent(bottomPad),
                    child: const _EmptyBlock(
                      title: '예정된 약속이 비어 있어요',
                      body: '장소가 확정된 약속이 여기에 모여요',
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: _HomeSpacing.bottomSectionContent(bottomPad),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _UpcomingAppointmentCard(
                        appointment: upcoming[index],
                        bottomMargin: index == upcoming.length - 1
                            ? 0
                            : _HomeSpacing.cardGap,
                      ),
                      childCount: upcoming.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final Color profileColor;
  final String userName;
  final bool profileLoading;
  final VoidCallback onCreate;
  final VoidCallback onChangeNickname;
  final VoidCallback onChangeColor;
  final VoidCallback onJoinByCode;
  final VoidCallback onSignOut;

  const _HomeHeader({
    required this.profileColor,
    required this.userName,
    required this.profileLoading,
    required this.onCreate,
    required this.onChangeNickname,
    required this.onChangeColor,
    required this.onJoinByCode,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: MobvWordmark(height: 38),
        ),
        const Spacer(),
        AppCircleIconButton(icon: Icons.add_rounded, onTap: onCreate),
        const SizedBox(width: 10),
        AppCircleIconButton(icon: Icons.key_outlined, onTap: onJoinByCode),
        const SizedBox(width: 10),
        GlassPopupMenu(
          alignRight: true,
          onSelected: (value) {
            if (value == 'nickname') onChangeNickname();
            if (value == 'color') onChangeColor();
            if (value == 'logout') onSignOut();
          },
          items: const [
            GlassMenuItem(
              value: 'nickname',
              icon: Icons.edit_outlined,
              label: '닉네임 변경',
            ),
            GlassMenuItem(
              value: 'color',
              icon: Icons.palette_outlined,
              label: '색상 변경',
            ),
            GlassMenuItem(
              value: 'logout',
              icon: Icons.logout_rounded,
              label: '로그아웃',
              destructive: true,
            ),
          ],
          child: _ProfileAvatar(
            color: profileColor,
            label: userName,
            size: 44,
            loading: profileLoading,
          ),
        ),
      ],
    );
  }
}

class _MeetingMapCard extends StatelessWidget {
  final int appointmentCount;
  final VoidCallback onTap;

  const _MeetingMapCard({required this.appointmentCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '우리의 만남 지도',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700, // w900 → w700
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      appointmentCount == 0
                          ? '참여한 약속이 생기면 여기에 모여요'
                          : '함께 만난 장소를 모아 기록해요',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.secondaryBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.map_rounded,
                  color: AppTheme.secondary,
                  size: 34,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700, // w900 → w700
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700, // w800 → w700
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

Map<String, dynamic> _memberProfilesFrom(Map<String, dynamic> data) {
  final profiles = Map<String, dynamic>.from(
    data['memberProfiles'] as Map? ?? {},
  );
  final members = List<String>.from(data['members'] ?? []);
  final names = Map<String, dynamic>.from(data['memberNames'] as Map? ?? {});
  final colors = Map<String, dynamic>.from(data['memberColors'] as Map? ?? {});
  return {
    for (final uid in members)
      uid: {
        'name':
            (profiles[uid] is Map ? (profiles[uid] as Map)['name'] : null)
                ?.toString() ??
            names[uid]?.toString() ??
            '',
        'color': profiles[uid] is Map
            ? ((profiles[uid] as Map)['color'] ?? colors[uid])
            : colors[uid],
      },
  };
}

class _AppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final bool compact;
  final double bottomMargin;
  final VoidCallback onTap;

  const _AppointmentCard({
    required this.appointment,
    required this.compact,
    required this.bottomMargin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (appointment['appointmentTitle'] ?? appointment['roomTitle'])
        ?.toString()
        .trim();
    final displayTitle = title == null || title.isEmpty ? '이름 없는 약속' : title;
    final members = List<String>.from(appointment['members'] ?? []);
    final memberProfiles = _memberProfilesFrom(appointment);
    final status = appointment['status']?.toString() ?? 'waiting';
    final inviteCode = appointment['inviteCode']?.toString().trim() ?? '';
    final badgeLabel = status == 'confirmed'
        ? null
        : '초대코드 ${inviteCode.isEmpty ? '-' : inviteCode}';

    return Padding(
      padding: EdgeInsets.only(bottom: bottomMargin),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              18,
              compact ? 14 : 17,
              16,
              compact ? 14 : 17,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600, // w900 → w600
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _MemberStack(
                            members: members,
                            memberProfiles: memberProfiles,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _AppointmentStatusBadge(status: status, label: badgeLabel),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpcomingAppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final double bottomMargin;

  const _UpcomingAppointmentCard({
    required this.appointment,
    required this.bottomMargin,
  });

  @override
  Widget build(BuildContext context) {
    final title = (appointment['appointmentTitle'] ?? appointment['roomTitle'])
        ?.toString()
        .trim();
    final displayTitle = title == null || title.isEmpty ? '이름 없는 약속' : title;
    final place = Map<String, dynamic>.from(
      appointment['confirmedPlace'] as Map? ?? {},
    );
    final placeName = place['name']?.toString().trim();
    final members = List<String>.from(appointment['members'] ?? []);
    final memberProfiles = _memberProfilesFrom(appointment);
    final appointmentDate = _dateFrom(appointment['appointmentDate']);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomMargin),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _formatDateTime(appointmentDate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700, // w900 → w700
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600, // w900 → w600
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placeName == null || placeName.isEmpty
                          ? '장소 이름 없음'
                          : placeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500, // w700 → w500
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: Material(
                        color: AppTheme.primaryBg,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _openMap(place),
                          child: const Icon(
                            Icons.map_outlined,
                            size: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _MemberStack(
                        members: members,
                        memberProfiles: memberProfiles,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime? _dateFrom(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return null;
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '일정 미정';
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '${date.month}월 ${date.day}일($weekday) $period $displayHour:$minute';
  }

  Future<void> _openMap(Map<String, dynamic> place) async {
    final url = _mapUrl(place);
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  }

  String? _mapUrl(Map<String, dynamic> place) {
    final directUrl = (place['url'] ?? place['kakaoUrl'])?.toString().trim();
    if (directUrl != null && directUrl.isNotEmpty) return directUrl;

    final name = place['name']?.toString().trim();
    final lat = (place['lat'] as num?)?.toDouble();
    final lng = (place['lng'] as num?)?.toDouble();
    if (name != null && name.isNotEmpty && lat != null && lng != null) {
      return 'https://map.kakao.com/link/map/${Uri.encodeComponent(name)},$lat,$lng';
    }
    if (name != null && name.isNotEmpty) {
      return 'https://map.kakao.com/link/search/${Uri.encodeComponent(name)}';
    }
    return null;
  }
}

class _MemberStack extends StatelessWidget {
  final List<String> members;
  final Map<String, dynamic> memberProfiles;

  const _MemberStack({required this.members, required this.memberProfiles});

  @override
  Widget build(BuildContext context) {
    final visible = members.take(5).toList();
    return SizedBox(
      width: visible.isEmpty ? 28 : 28.0 + (visible.length - 1) * 16,
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * 16,
              child: _ProfileAvatar(
                color: Color(_memberColor(visible[i])),
                label: _memberName(visible[i]),
                size: 28,
                borderColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  int _memberColor(String uid) {
    final profile = Map<String, dynamic>.from(
      memberProfiles[uid] as Map? ?? {},
    );
    final stored = profile['color'];
    if (stored is num) return stored.toInt();
    return _fallbackColor(uid);
  }

  String _memberName(String uid) {
    final profile = Map<String, dynamic>.from(
      memberProfiles[uid] as Map? ?? {},
    );
    return profile['name']?.toString() ?? '';
  }

  int _fallbackColor(String uid) {
    final hash = uid.codeUnits.fold<int>(0, (total, code) => total + code);
    final colors = AuthService.profileColorValues;
    return colors[hash % colors.length];
  }
}

class _ProfileAvatar extends StatelessWidget {
  final Color color;
  final String label;
  final double size;
  final Color? borderColor;
  final bool loading;

  const _ProfileAvatar({
    required this.color,
    required this.label,
    required this.size,
    this.borderColor,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasLabel = label.trim().isNotEmpty;
    final initial = hasLabel ? label.trim().characters.first : '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: loading ? AppTheme.surface : color,
        shape: BoxShape.circle,
        border: borderColor == null
            ? Border.all(color: AppTheme.border)
            : Border.all(color: borderColor!, width: 2),
      ),
      child: Center(
        child: loading || !hasLabel
            ? Icon(
                Icons.person_rounded,
                color: AppTheme.textMuted,
                size: size * 0.5,
              )
            : Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w700, // w900 → w700
                ),
              ),
      ),
    );
  }
}

class _AppointmentStatusBadge extends StatelessWidget {
  final String status;
  final String? label;

  const _AppointmentStatusBadge({required this.status, this.label});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? _statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700, // w900 → w700
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'date_voting' => const Color(0xFF6366F1),
      'drawing' || 'circleReady' => AppTheme.drawing,
      'voting' || 'recommended' => AppTheme.voting,
      'confirmed' => AppTheme.secondary,
      _ => AppTheme.primary,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'date_voting' => '날짜 조율',
      'drawing' => '범위 입력',
      'voting' => '장소 선택',
      'dateReady' => '날짜 완료',
      'circleReady' => '범위 완료',
      'recommended' => '추천 완료',
      'confirmed' => '확정',
      _ => '준비 중',
    };
  }
}

class _EmptyBlock extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600, // w800 → w600
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  final int selectedColor;

  const _ColorPickerDialog({required this.selectedColor});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '나의 색상',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700, // w900 → w700
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '프로필과 지도 원에 함께 쓰일 색상이에요',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final value in AuthService.profileColorValues)
                  _ColorDot(
                    value: value,
                    selected: value == selectedColor,
                    onTap: () => Navigator.pop(context, value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Color(value),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.textDark : Colors.white,
            width: selected ? 3 : 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

class _JoinDialog extends StatefulWidget {
  final TextEditingController controller;

  const _JoinDialog({required this.controller});

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  void _submit() {
    final code = widget.controller.text.trim().toUpperCase();
    if (code.isEmpty) return;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '코드로 참여',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700, // w900 → w700
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '초대 코드 6자리를 입력하세요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
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
                fontWeight: FontWeight.w700, // w800 → w700
                letterSpacing: 10,
                color: AppTheme.textDark,
              ),
              decoration: InputDecoration(
                hintText: '......',
                hintStyle: const TextStyle(
                  color: AppTheme.border,
                  letterSpacing: 10,
                ),
                filled: true,
                fillColor: AppTheme.bg,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.textDark,
                side: const BorderSide(color: AppTheme.border, width: 1),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                '참여하기',
                style: TextStyle(fontWeight: FontWeight.w700), // w800 → w700
              ),
            ),
          ],
        ),
      ),
    );
  }
}