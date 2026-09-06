import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobv/app_theme.dart';
import 'package:mobv/widgets/gradient_button.dart';
import 'package:mobv/widgets/mobv_brand.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  void _showComingSoon(BuildContext context, String provider) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$provider 로그인은 곧 연결할게요')));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MobvSymbol(size: 70),
                    SizedBox(height: 18),
                    MobvWordmark(height: 42),
                    SizedBox(height: 18),
                    Text(
                      '모두가 괜찮은 곳에서 만나요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textBody,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Where everyone meets.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),
              _AuthProviderButton(
                label: '카카오 로그인',
                backgroundColor: const Color(0xFFFEE500),
                foregroundColor: const Color(0xFF191919),
                borderColor: const Color(0xFFFEE500),
                icon: const _KakaoMark(),
                onTap: () => _showComingSoon(context, '카카오'),
              ),
              const SizedBox(height: 12),
              _AuthProviderButton(
                label: 'Google로 로그인',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1F1F1F),
                borderColor: const Color(0xFFDADCE0),
                icon: const _GoogleMark(),
                onTap: () => _showComingSoon(context, '구글'),
              ),
              const SizedBox(height: 12),
              _AuthProviderButton(
                label: '이메일 로그인',
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                borderColor: AppTheme.primary,
                icon: const Icon(
                  Icons.mail_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
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
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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
        return '아이디 또는 비밀번호가 올바르지 않아요';
      case 'email-already-in-use':
        return '이미 사용 중인 아이디예요';
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

  void _toggleSignup() {
    setState(() {
      _isLogin = !_isLogin;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  bottomPad,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 56),
                  Text(
                    _isLogin ? '이메일 로그인' : '회원가입',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin ? '아이디와 비밀번호로 계속해요' : 'Mobv에서 사용할 계정을 만들어요',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (!_isLogin) ...[
                    _FormField(
                      controller: _nameController,
                      hint: '닉네임',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _FormField(
                    controller: _emailController,
                    hint: '아이디',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _FormField(
                    controller: _passwordController,
                    hint: '비밀번호',
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _error == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 14,
                                  color: AppTheme.error,
                                ),
                                const SizedBox(width: 6),
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
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.textDark,
                        disabledBackgroundColor: AppTheme.disabledBg,
                        disabledForegroundColor: AppTheme.disabled,
                        side: const BorderSide(color: AppTheme.border, width: 1),
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
                                color: AppTheme.textDark,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isLogin ? '로그인' : '회원가입',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: _toggleSignup,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textMuted,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(_isLogin ? '회원가입' : '로그인으로 돌아가기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthProviderButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final Widget icon;
  final VoidCallback onTap;

  const _AuthProviderButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(left: 18, child: icon),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: foregroundColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KakaoMark extends StatelessWidget {
  const _KakaoMark();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.chat_bubble_rounded,
      color: Color(0xFF191919),
      size: 19,
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            color: Color(0xFF4285F4),
            fontSize: 17,
            fontWeight: FontWeight.w900,
            fontFamily: 'Roboto',
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
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
