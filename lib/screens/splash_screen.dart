import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_screen.dart';
import 'room_list_screen.dart';
import 'package:mobv/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );

    // 0~22%: 페이드인
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.22, curve: Curves.easeIn),
      ),
    );

    // 78~100%: 페이드아웃
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.78, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward().then((_) {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, _, _) =>
              user != null ? const RoomListScreen() : const AuthScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          // 페이드인이 끝나기 전엔 fadeIn, 이후엔 fadeOut 적용
          final opacity = _controller.value < 0.78
              ? _fadeIn.value
              : _fadeOut.value;
          return Opacity(opacity: opacity, child: child);
        },
        child: const Center(child: MobvLogo(fontSize: 52)),
      ),
    );
  }
}

// 공용 로고 위젯
class MobvLogo extends StatelessWidget {
  final double fontSize;
  const MobvLogo({super.key, this.fontSize = 52});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Text(
          'Mobv',
          style: TextStyle(
            fontFamily: 'Pacifico',
            fontSize: fontSize,
            color: Colors.white,
          ),
        ),
        Positioned(
          left: -8,
          top: -(fontSize * 0.7),
          child: _LocationPin(size: fontSize * 0.62),
        ),
        Positioned(
          right: -8,
          top: -(fontSize * 0.7),
          child: _ChatBubble(width: fontSize * 0.75, height: fontSize * 0.65),
        ),
      ],
    );
  }
}

class _LocationPin extends StatelessWidget {
  final double size;
  const _LocationPin({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.73,
      height: size,
      child: CustomPaint(painter: _PinPainter()),
    );
  }
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..cubicTo(
        size.width / 2,
        size.height * 0.7,
        0,
        size.height * 0.55,
        0,
        size.height * 0.35,
      )
      ..arcToPoint(
        Offset(size.width, size.height * 0.35),
        radius: Radius.circular(size.width / 2),
        clockwise: false,
      )
      ..cubicTo(
        size.width,
        size.height * 0.55,
        size.width / 2,
        size.height * 0.7,
        size.width / 2,
        size.height,
      )
      ..close();
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawPath(path, strokePaint);
    final circlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.35),
      size.width * 0.2,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChatBubble extends StatelessWidget {
  final double width;
  final double height;
  const _ChatBubble({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _BubblePainter()),
    );
  }
}

class _BubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final dotPaint = Paint()..color = AppTheme.primary;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.72),
      const Radius.circular(7),
    );
    canvas.drawRRect(rrect, paint);
    final tail = Path()
      ..moveTo(size.width * 0.2, size.height * 0.7)
      ..lineTo(size.width * 0.35, size.height)
      ..lineTo(size.width * 0.5, size.height * 0.7)
      ..close();
    canvas.drawPath(tail, paint);
    final dotY = size.height * 0.36;
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.25 + i * 0.25), dotY),
        size.width * 0.07,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
