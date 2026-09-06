import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobv/app_theme.dart';
import '../models/date_coordination_model.dart';
import '../services/appointment_service.dart';
import 'map_screen.dart';

class DateCoordinationScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final int myProfileColor;
  final List<String> members;

  const DateCoordinationScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.myProfileColor,
    required this.members,
  });

  @override
  State<DateCoordinationScreen> createState() => _DateCoordinationScreenState();
}

class _DateCoordinationScreenState extends State<DateCoordinationScreen> {
  final _roomService = AppointmentService();

  StreamSubscription? _roomSub;
  StreamSubscription? _votesSub;

  Map<String, dynamic>? _roomData;
  List<DateVote> _votes = [];
  bool _isLoading = false;

  // 내가 선택한 날짜와 시간대
  final Set<String> _mySelectedDates = {};
  final Set<String> _mySelectedSlots = {};

  // 달력 현재 표시 월
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // 방장이 확정용으로 선택한 날짜와 시간대
  String? _hostSelectedDate;
  TimeSlot _hostSelectedSlot = TimeSlot.afternoon;

  bool get _isHost =>
      _roomData != null && _roomData!['createdBy'] == widget.myUserId;

  @override
  void initState() {
    super.initState();
    _subscribeRoom();
    _subscribeVotes();
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _votesSub?.cancel();
    super.dispose();
  }

  void _subscribeRoom() {
    _roomSub = _roomService.watchAppointment(widget.roomId).listen((room) {
      if (!mounted || room == null) return;
      setState(() => _roomData = room);

      // 만약 방장이 날짜를 확정하여 status가 drawing으로 바뀌었으면 지도 화면으로 이동
      if (room['status'] == 'drawing' || room['status'] == 'circleReady') {
        _navigateToMap();
      }
    });
  }

  void _subscribeVotes() {
    _votesSub = _roomService.watchDateVotes(widget.roomId).listen((votes) {
      if (!mounted) return;
      setState(() {
        _votes = votes;
        // 내 기존 투표 내역이 있으면 초기화 시 반영
        final myVote = votes.where((v) => v.userId == widget.myUserId).firstOrNull;
        if (myVote != null && _mySelectedDates.isEmpty && _mySelectedSlots.isEmpty) {
          _mySelectedDates.addAll(myVote.availableDates);
          _mySelectedSlots.addAll(myVote.availableTimeSlots);
        }
      });
    });
  }

  void _navigateToMap() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          roomId: widget.roomId,
          myUserId: widget.myUserId,
          myUserName: widget.myUserName,
          members: List<String>.from(_roomData?['members'] ?? widget.members),
        ),
      ),
    );
  }

  // 투표 집계 계산
  List<DateSlotAggregate> _calculateAggregates() {
    final allDates = <String>{};
    for (final v in _votes) {
      allDates.addAll(v.availableDates);
    }
    allDates.addAll(_mySelectedDates);

    final rawCandidates = List<dynamic>.from(_roomData?['candidateDates'] ?? []);
    if (rawCandidates.isNotEmpty) {
      allDates.addAll(rawCandidates.map((e) => e.toString()));
    }

    final List<DateSlotAggregate> aggregates = [];

    for (final dateStr in allDates) {
      final parts = dateStr.split('-');
      if (parts.length != 3) continue;
      final dt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));

      final matchingUserIds = <String>[];
      final Map<TimeSlot, List<String>> slotMembers = {
        for (final s in TimeSlot.values) s: [],
      };

      for (final v in _votes) {
        if (v.availableDates.contains(dateStr)) {
          matchingUserIds.add(v.userId);
          for (final slotName in v.availableTimeSlots) {
            final slot = TimeSlot.fromKey(slotName);
            if (slot != null) {
              slotMembers[slot]?.add(v.userId);
            }
          }
        }
      }

      aggregates.add(DateSlotAggregate(
        dateString: dateStr,
        dateTime: dt,
        memberUserIds: matchingUserIds,
        timeSlotMembers: slotMembers,
      ));
    }

    // 가능 인원 많은 순 정렬 (동률이면 날짜 빠른 순)
    aggregates.sort((a, b) {
      final cmp = b.memberCount.compareTo(a.memberCount);
      if (cmp != 0) return cmp;
      return a.dateTime.compareTo(b.dateTime);
    });
    return aggregates;
  }

  Future<void> _saveMyVote() async {
    if (_mySelectedDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가능한 날짜를 최소 1개 이상 선택해주세요')),
      );
      return;
    }
    if (_mySelectedSlots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선호하는 시간대를 1개 이상 선택해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final vote = DateVote(
        userId: widget.myUserId,
        userName: widget.myUserName,
        profileColor: widget.myProfileColor,
        availableDates: _mySelectedDates.toList(),
        availableTimeSlots: _mySelectedSlots.toList(),
      );

      await _roomService.submitDateVote(roomId: widget.roomId, vote: vote);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내 가능 날짜/시간이 저장되었어요!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDateByHost(DateSlotAggregate bestOption) async {
    final targetDateStr = _hostSelectedDate ?? bestOption.dateString;
    final parts = targetDateStr.split('-');
    final targetDate = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
      _hostSelectedSlot == TimeSlot.lunch
          ? 12
          : (_hostSelectedSlot == TimeSlot.afternoon
              ? 15
              : (_hostSelectedSlot == TimeSlot.dinner ? 18 : 20)),
    );

    setState(() => _isLoading = true);
    try {
      await _roomService.confirmAppointmentDate(
        roomId: widget.roomId,
        confirmedDate: targetDate,
        timeSlot: _hostSelectedSlot.name,
      );
      // confirm 후 stream 감지로 _navigateToMap 자동 호출됨
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('확정 오류: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _roomData?['appointmentTitle'] ?? '약속 날짜 조율';
    final inviteCode = _roomData?['inviteCode'] ?? '';
    final allMembers = List<String>.from(_roomData?['members'] ?? widget.members);
    final memberProfiles = Map<String, dynamic>.from(_roomData?['memberProfiles'] ?? {});
    final aggregates = _calculateAggregates();
    final bestOption = aggregates.firstOrNull;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              '함께 모일 날짜와 시간대를 정해보세요',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          if (inviteCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ActionChip(
                backgroundColor: AppTheme.primaryBg,
                avatar: const Icon(Icons.copy_rounded, size: 14, color: AppTheme.primary),
                label: Text(
                  '코드 $inviteCode',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('초대 코드 $inviteCode 복사 완료!')),
                  );
                },
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              // 1. 멤버 참여 현황 스트립
              _buildMemberStatusBar(allMembers, memberProfiles),
              const SizedBox(height: 24),

              // 2. 실시간 최다 겹침 순위 (1위 하이라이트)
              if (bestOption != null && bestOption.memberCount > 0)
                _buildBestOptionCard(bestOption, allMembers.length),
              const SizedBox(height: 24),

              // 3. 내 가능한 날짜 달력에서 선택
              _buildSectionTitle('📅 내가 가능한 날짜 선택 (달력 탭)'),
              const SizedBox(height: 12),
              _buildMonthlyCalendarView(),
              const SizedBox(height: 24),

              // 4. 선호 시간대 선택
              _buildSectionTitle('⏰ 선호하는 시간대'),
              const SizedBox(height: 12),
              _buildTimeSlotSelector(),
              const SizedBox(height: 24),

              // 5. 방장 전용 최종 확정 옵션
              if (_isHost && bestOption != null)
                _buildHostConfirmSection(aggregates, allMembers.length),
            ],
          ),

          // 하단 고정 바텀 액션바
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomActionBar(bestOption, allMembers.length),
          ),
        ],
      ),
    );
  }

  // 멤버 상태 바
  Widget _buildMemberStatusBar(List<String> members, Map<String, dynamic> profiles) {
    final votedUids = _votes.map((v) => v.userId).toSet();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '투표 현황 (${votedUids.length}/${members.length}명 완료)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
              if (votedUids.length == members.length)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: Color(0xFF2E7D32)),
                      SizedBox(width: 4),
                      Text(
                        '전원 완료!',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: members.map((uid) {
              final isVoted = votedUids.contains(uid);
              final prof = profiles[uid] as Map<String, dynamic>?;
              final name = prof?['name'] ?? (uid == widget.myUserId ? widget.myUserName : '멤버');
              final colorVal = prof?['color'] ?? widget.myProfileColor;
              final color = Color(colorVal);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: color, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0] : '?',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: BoxDecoration(
                            color: isVoted ? const Color(0xFF22C55E) : Colors.grey.shade400,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: isVoted
                              ? const Icon(Icons.check, size: 9, color: Colors.white)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name.length > 3 ? '${name.substring(0, 3)}..' : name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isVoted ? FontWeight.w700 : FontWeight.w500,
                      color: isVoted ? AppTheme.textDark : AppTheme.textMuted,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 1순위 최다 겹침 결과 카드
  Widget _buildBestOptionCard(DateSlotAggregate best, int totalMembers) {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdays[best.dateTime.weekday - 1];
    final slot = best.mostPopularSlot ?? TimeSlot.afternoon;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('👑', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '가장 많이 모일 수 있는 날',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${best.memberCount}/$totalMembers명 가능',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${best.dateTime.month}월 ${best.dateTime.day}일 ($wd) · ${slot.label}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 월간 달력 기반 날짜 다중 선택 뷰
  Widget _buildMonthlyCalendarView() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final year = _calendarMonth.year;
    final month = _calendarMonth.month;

    // 해당 월의 1일
    final firstDayOfMonth = DateTime(year, month, 1);
    // 일요일 시작 오프셋 (일=0, 월=1, ... 토=6)
    final firstDayOffset = firstDayOfMonth.weekday % 7;
    // 해당 월의 총 일수
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final isCurrentMonth = year == now.year && month == now.month;
    final canGoPrev = !isCurrentMonth;
    final canGoNext = _calendarMonth.isBefore(DateTime(now.year, now.month + 3, 1));

    final weekdays = ['일', '월', '화', '수', '목', '금', '토'];

    // 날짜별 투표 인원 맵 생성
    final Map<String, int> votesPerDate = {};
    for (final v in _votes) {
      for (final d in v.availableDates) {
        votesPerDate[d] = (votesPerDate[d] ?? 0) + 1;
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // 월 네비게이션 헤더
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: canGoPrev
                    ? () {
                        setState(() {
                          _calendarMonth = DateTime(year, month - 1, 1);
                        });
                      }
                    : null,
                color: canGoPrev ? AppTheme.textDark : Colors.grey.shade300,
              ),
              Text(
                '$year년 $month월',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: canGoNext
                    ? () {
                        setState(() {
                          _calendarMonth = DateTime(year, month + 1, 1);
                        });
                      }
                    : null,
                color: canGoNext ? AppTheme.textDark : Colors.grey.shade300,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 요일 헤더
          Row(
            children: weekdays.asMap().entries.map((entry) {
              final idx = entry.key;
              final wd = entry.value;
              final isWeekend = idx == 0 || idx == 6;

              return Expanded(
                child: Center(
                  child: Text(
                    wd,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isWeekend
                          ? (idx == 0 ? Colors.redAccent : Colors.blueAccent)
                          : AppTheme.textMuted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 날짜 그리드
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstDayOffset + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 4,
              mainAxisSpacing: 6,
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, index) {
              if (index < firstDayOffset) {
                return const SizedBox.shrink();
              }

              final day = index - firstDayOffset + 1;
              final cellDate = DateTime(year, month, day);
              final isPast = cellDate.isBefore(today);
              final isToday = cellDate == today;

              final dateStr =
                  '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isSelected = _mySelectedDates.contains(dateStr);
              final voteCount = votesPerDate[dateStr] ?? 0;

              final weekdayIdx = cellDate.weekday % 7;
              final isWeekend = weekdayIdx == 0 || weekdayIdx == 6;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: isPast
                    ? null
                    : () {
                        setState(() {
                          if (isSelected) {
                            _mySelectedDates.remove(dateStr);
                          } else {
                            _mySelectedDates.add(dateStr);
                          }
                        });
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary
                        : (isToday ? AppTheme.primaryBg : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: AppTheme.primary, width: 1.5)
                        : (isToday
                            ? Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.5),
                                width: 1.2,
                              )
                            : null),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isPast
                                  ? Colors.grey.shade300
                                  : (isWeekend
                                      ? (weekdayIdx == 0
                                          ? Colors.redAccent
                                          : Colors.blueAccent)
                                      : AppTheme.textDark)),
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (voteCount > 0 && !isPast)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$voteCount명',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : AppTheme.primary,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 14),

          // 선택 요약
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '달력의 날짜를 탭하여 가능 일정을 등록하세요',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${_mySelectedDates.length}일 선택됨',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 시간대 선택
  Widget _buildTimeSlotSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: TimeSlot.values.map((slot) {
        final isSelected = _mySelectedSlots.contains(slot.name);

        return FilterChip(
          selected: isSelected,
          avatar: Text(slot.emoji, style: const TextStyle(fontSize: 14)),
          label: Text('${slot.label} (${slot.timeRange})'),
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.textDark,
          ),
          selectedColor: AppTheme.primary,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSelected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _mySelectedSlots.add(slot.name);
              } else {
                _mySelectedSlots.remove(slot.name);
              }
            });
          },
        );
      }).toList(),
    );
  }

  // 방장 확정 설정 섹션
  Widget _buildHostConfirmSection(List<DateSlotAggregate> aggregates, int totalMembers) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '방장 권한',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '최종 날짜 확정 옵션',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '방장은 다른 날짜나 시간대를 직접 선택해 바로 장소 결정(원 그리기)으로 넘어갈 수 있습니다.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _hostSelectedDate ?? aggregates.first.dateString,
            decoration: InputDecoration(
              labelText: '확정할 날짜 선택',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: aggregates.map((agg) {
              return DropdownMenuItem(
                value: agg.dateString,
                child: Text(
                  '${agg.dateTime.month}/${agg.dateTime.day} (${agg.memberCount}/$totalMembers명 가능)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _hostSelectedDate = val);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TimeSlot>(
            initialValue: _hostSelectedSlot,
            decoration: InputDecoration(
              labelText: '확정할 시간대',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: TimeSlot.values.map((slot) {
              return DropdownMenuItem(
                value: slot,
                child: Text('${slot.emoji} ${slot.label} (${slot.timeRange})'),
              );
            }).toList(),
            onChanged: (slot) {
              if (slot != null) setState(() => _hostSelectedSlot = slot);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppTheme.textDark,
      ),
    );
  }

  // 바텀 고정 버튼
  Widget _buildBottomActionBar(DateSlotAggregate? bestOption, int totalMembers) {
    final myVoteSubmitted = _votes.any((v) => v.userId == widget.myUserId);
    final hasConfirmButton = _isHost && bestOption != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 1. 내 투표 저장 버튼
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveMyVote,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasConfirmButton ? AppTheme.primaryBg : Colors.white,
                foregroundColor: AppTheme.textDark,
                elevation: 0,
                side: const BorderSide(color: AppTheme.border, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                myVoteSubmitted ? '내 가능 시간 수정' : '내 가능 시간 저장',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ),

          // 2. 방장인 경우: 최종 확정 후 위치 정하러 가기
          if (hasConfirmButton) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : () => _confirmDateByHost(bestOption),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.textDark,
                  elevation: 0,
                  side: const BorderSide(color: AppTheme.border, width: 1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '날짜 확정하기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, color: AppTheme.textDark, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
