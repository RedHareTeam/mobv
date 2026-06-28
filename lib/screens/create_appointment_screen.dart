import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';
import '../services/auth_service.dart';
import '../services/appointment_service.dart';
import '../widgets/gradient_button.dart';
import 'map_screen.dart';

class CreateAppointmentScreen extends StatefulWidget {
  const CreateAppointmentScreen({super.key});

  @override
  State<CreateAppointmentScreen> createState() =>
      _CreateAppointmentScreenState();
}

class _CreateAppointmentScreenState extends State<CreateAppointmentScreen> {
  final _authService = AuthService();
  final _roomService = AppointmentService();
  final _titleController = TextEditingController();
  static const int _defaultMaxMembers = 99;
  String _category = 'cafe';
  bool _loading = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  String get _myUserId => _authService.currentUser?.uid ?? '';
  String _myUserName = '';
  int _myProfileColor = AuthService.profileColorValues.first;

  bool get _canSubmit {
    if (_titleController.text.trim().isEmpty) {
      return false;
    }
    if (_selectedDate == null || _selectedTime == null) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _titleController.addListener(() => setState(() {}));
  }

  Future<void> _loadUserName() async {
    final info = await _authService.getUserInfo(_myUserId);
    if (!mounted) return;
    setState(() {
      _myUserName = info?['userName'] ?? '';
      _myProfileColor =
          (info?['profileColor'] as num?)?.toInt() ??
          _authService.fallbackProfileColor(_myUserId);
    });
  }

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

  String _formatDate(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}년 ${dt.month}월 ${dt.day}일 (${weekdays[dt.weekday - 1]})';
  }

  String _formatTime(TimeOfDay time) {
    final period = time.hour < 12 ? '오전' : '오후';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$period $hour:$minute';
  }

  DateTime _appointmentDateTime() {
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('약속 이름을 입력해주세요')));
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('날짜와 시간을 선택해주세요')));
      return;
    }

    setState(() => _loading = true);

    final roomId = await _roomService.createAppointment(
      myUserId: _myUserId,
      myUserName: _myUserName,
      myProfileColor: _myProfileColor,
      appointmentTitle: _titleController.text.trim(),
      category: _category,
      maxMembers: _defaultMaxMembers,
      appointmentDate: _appointmentDateTime(),
    );
    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          roomId: roomId,
          myUserId: _myUserId,
          myUserName: _myUserName,
          members: [_myUserId],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
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
                        '새 약속 만들기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppCircleIconButton(
                          icon: Icons.check_rounded,
                          enabled: _canSubmit,
                          loading: _loading,
                          size: 38,
                          iconSize: 22,
                          onTap: _submit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '약속 이름',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppTheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
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
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    '약속 날짜',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '만날 날짜와 시간을 정해주세요',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  _PickerTile(
                    icon: Icons.calendar_month_rounded,
                    label: _selectedDate != null
                        ? _formatDate(_selectedDate!)
                        : '날짜를 선택하세요',
                    isSelected: _selectedDate != null,
                    onTap: _pickDate,
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
                  const SizedBox(height: 28),

                  const Text(
                    '장소 카테고리',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '이번 약속에서 찾고 싶은 장소 유형을 선택하세요',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        const [
                          _CategoryChoice(label: '카페', value: 'cafe'),
                          _CategoryChoice(label: '맛집', value: 'restaurant'),
                          _CategoryChoice(label: '술집', value: 'bar'),
                          _CategoryChoice(label: '스터디', value: 'study'),
                        ].map((choice) {
                          final selected = _category == choice.value;
                          return ChoiceChip(
                            label: Text(choice.label),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _category = choice.value),
                            selectedColor: AppTheme.primary.withValues(
                              alpha: 0.18,
                            ),
                            backgroundColor: AppTheme.surface,
                            labelStyle: TextStyle(
                              color: selected
                                  ? AppTheme.primary
                                  : AppTheme.textDark,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? AppTheme.primary.withValues(alpha: 0.45)
                                  : AppTheme.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '다음 단계',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '약속을 만든 뒤 초대 코드로 멤버를 모으고, 각자의 이동 가능 원을 입력해 장소를 추천받아요.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
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

class _CategoryChoice {
  final String label;
  final String value;

  const _CategoryChoice({required this.label, required this.value});
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
