import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';
import '../services/room_service.dart';
import '../widgets/gradient_button.dart';
import 'map_screen.dart';

class DateSettingScreen extends StatefulWidget {
  final String roomId;
  final String myUserId;
  final String myUserName;
  final int maxMembers;
  final List<String> members;

  const DateSettingScreen({
    super.key,
    required this.roomId,
    required this.myUserId,
    required this.myUserName,
    required this.maxMembers,
    required this.members,
  });

  @override
  State<DateSettingScreen> createState() => _DateSettingScreenState();
}

class _DateSettingScreenState extends State<DateSettingScreen> {
  final _roomService = RoomService();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _loading = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            onSurface: AppTheme.textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 14, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _confirm() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('날짜와 시간을 모두 선택해주세요')));
      return;
    }
    setState(() => _loading = true);

    final dt = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    await _roomService.setDrawingStatus(widget.roomId, dt);
    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          roomId: widget.roomId,
          myUserId: widget.myUserId,
          myUserName: widget.myUserName,
          members: widget.members,
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 (${weekdays[dt.weekday - 1]})';
  }

  String _formatTime(TimeOfDay t) {
    final period = t.hour < 12 ? '오전' : '오후';
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selectedDate != null && _selectedTime != null;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
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
            title: const Text(
              '약속 날짜 설정',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: CircleForwardButton(
                  enabled: canConfirm,
                  loading: _loading,
                  onTap: _confirm,
                ),
              ),
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 안내 배너
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.primary,
                                    AppTheme.gradientEnd,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '날짜를 설정하면 지도가 열리고\n${widget.maxMembers}명 모두 원을 그릴 수 있어요',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primary,
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // 날짜 선택
                  const Text(
                    '날짜 선택',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PickerTile(
                    icon: Icons.calendar_month_rounded,
                    label: _selectedDate != null
                        ? _formatDate(_selectedDate!)
                        : '날짜를 선택하세요',
                    isSelected: _selectedDate != null,
                    onTap: _pickDate,
                  ),

                  const SizedBox(height: 16),

                  // 시간 선택
                  const Text(
                    '시간 선택',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PickerTile(
                    icon: Icons.access_time_rounded,
                    label: _selectedTime != null
                        ? _formatTime(_selectedTime!)
                        : '시간을 선택하세요',
                    isSelected: _selectedTime != null,
                    onTap: _pickTime,
                  ),

                  const Spacer(),

                  // 약속 요약 카드
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: canConfirm
                        ? Container(
                            key: const ValueKey('summary'),
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.cardGradientStart,
                                  AppTheme.cardGradientEnd,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.25),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '약속 요약',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatDate(_selectedDate!),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(_selectedTime!),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
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

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [
                    AppTheme.cardGradientStart,
                    AppTheme.cardGradientEnd,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary.withValues(alpha: 0.4)
                : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.gradientEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AppTheme.disabled,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.textDark : AppTheme.textMuted,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isSelected ? AppTheme.primary : AppTheme.disabled,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
