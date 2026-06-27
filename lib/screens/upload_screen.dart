import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';
import '../services/auth_service.dart';
import '../services/room_service.dart';
import '../widgets/gradient_button.dart';
import 'room_home_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _authService = AuthService();
  final _roomService = RoomService();
  final _titleController = TextEditingController();
  int _memberCount = 2;
  String _category = 'cafe';
  bool _loading = false;

  String get _myUserId => _authService.currentUser?.uid ?? '';
  String _myUserName = '';

  bool get _canSubmit {
    if (_titleController.text.trim().isEmpty) {
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
    if (mounted) setState(() => _myUserName = info?['userName'] ?? '');
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('방 제목을 입력해주세요')));
      return;
    }

    setState(() => _loading = true);

    final roomId = await _roomService.createRoom(
      myUserId: _myUserId,
      myUserName: _myUserName,
      roomTitle: _titleController.text.trim(),
      category: _category,
      maxMembers: _memberCount,
    );
    final room = await _roomService.getRoom(roomId);
    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'RoomHomeScreen'),
        builder: (_) => RoomHomeScreen(
          roomId: roomId,
          myUserId: _myUserId,
          myUserName: _myUserName,
          maxMembers: _memberCount,
          initialRoomData: room,
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
              '새 방 만들기',
              style: const TextStyle(
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
                  enabled: _canSubmit,
                  loading: _loading,
                  onTap: _submit,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '방 제목',
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
                    '인원 설정',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '본인 포함 총 인원 수를 선택하세요',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(4, (i) {
                      final count = i + 2;
                      final selected = _memberCount == count;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _memberCount = count),
                            borderRadius: BorderRadius.circular(18),
                            splashFactory: NoSplash.splashFactory,
                            highlightColor: Colors.black.withValues(
                              alpha: 0.06,
                            ),
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? const LinearGradient(
                                        colors: [
                                          AppTheme.primary,
                                          AppTheme.gradientEnd,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: selected ? null : AppTheme.surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? Colors.transparent
                                      : AppTheme.border,
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.primary.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: selected
                                          ? Colors.white
                                          : AppTheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '명',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? Colors.white70
                                          : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),

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
                          '방을 만든 뒤 초대 코드로 멤버를 모으고, 날짜와 각자의 이동 가능 원을 입력해 장소를 추천받아요.',
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
