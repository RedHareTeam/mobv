import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:mobv/app_theme.dart';
import 'package:mobv/widgets/mobv_brand.dart';
import 'room_list_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _toggleMode() => setState(() {
    _isLogin = !_isLogin;
    _error = null;
  });

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isLogin) {
        await _authService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          userName: _nameController.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoomListScreen()),
        (_) => false,
      );
    } catch (e) {
      final code = switch (e) {
        FirebaseAuthException() => e.code,
        FirebaseException() => e.code,
        _ => e.toString(),
      };
      debugPrint('Auth error: $code / $e');
      setState(() => _error = _friendlyError(code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않아요';
      case 'email-already-in-use':
        return '이미 사용 중인 이메일이에요';
      case 'weak-password':
        return '비밀번호는 6자 이상이어야 해요';
      case 'invalid-email':
        return '올바른 이메일 형식이 아니에요';
      case 'network-request-failed':
        return '네트워크 연결을 확인해주세요';
      case 'too-many-requests':
        return '잠시 후 다시 시도해주세요';
      case 'operation-not-allowed':
        return 'Firebase에서 이메일/비밀번호 로그인이 꺼져 있어요';
      case 'unauthorized-domain':
        return 'Firebase Auth에 현재 웹 도메인이 허용되어 있지 않아요';
      case 'permission-denied':
        return 'Firestore 사용자 정보 저장 권한이 막혀 있어요';
      default:
        return '오류가 발생했어요. 다시 시도해주세요 ($code)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.primary,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 브랜드 영역
                    Expanded(
                      flex: 2,
                      child: Container(
                        color: const Color(0xFFF4F5F8),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MobvSymbol(size: 58),
                              SizedBox(height: 16),
                              MobvWordmark(height: 36),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 폼 카드
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 탭 토글
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.bg,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Stack(
                              children: [
                                // 슬라이딩 흰색 인디케이터
                                AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  alignment: _isLogin
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: FractionallySizedBox(
                                    widthFactor: 0.5,
                                    child: Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.07,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // 탭 라벨
                                Row(
                                  children: [
                                    _ToggleTab(
                                      label: '로그인',
                                      selected: _isLogin,
                                      onTap: () {
                                        if (!_isLogin) _toggleMode();
                                      },
                                    ),
                                    _ToggleTab(
                                      label: '회원가입',
                                      selected: !_isLogin,
                                      onTap: () {
                                        if (_isLogin) _toggleMode();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 닉네임 (회원가입 시)
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            child: _isLogin
                                ? const SizedBox.shrink()
                                : Column(
                                    children: [
                                      _FormField(
                                        controller: _nameController,
                                        hint: '닉네임',
                                        icon: Icons.person_outline_rounded,
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                          ),

                          // 이메일
                          _FormField(
                            controller: _emailController,
                            hint: '이메일',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),

                          // 비밀번호
                          _FormField(
                            controller: _passwordController,
                            hint: '비밀번호',
                            icon: Icons.lock_outline_rounded,
                            obscureText: true,
                          ),

                          // 에러
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: _error == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.info_outline_rounded,
                                          size: 13,
                                          color: AppTheme.error,
                                        ),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(
                                            _error!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppTheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),

                          const SizedBox(height: 20),

                          // 제출 버튼
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppTheme.disabled,
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ).copyWith(elevation: WidgetStateProperty.all(0)),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _isLogin ? '로그인' : '회원가입',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: bottomPad + 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: double.infinity,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.primary : AppTheme.textMuted,
                fontFamily: 'Pretendard',
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;

  const _FormField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 15,
        color: AppTheme.textDark,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
        filled: true,
        fillColor: AppTheme.bg,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
