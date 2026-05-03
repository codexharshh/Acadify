import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_page.dart';
import 'login_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // Navigate after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      final user = FirebaseAuth.instance.currentUser;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              user != null ? const DashboardPage() : const LoginPage(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Icon size is responsive: 22% of screen width, clamped for phone/tablet/web.
    // Responsive icon size: phone gets smaller, laptop/web gets larger
    final double iconSize;
    if (screenWidth < 600) {
      iconSize = screenWidth * 0.21; // phone: ~75px on 360px screen
    } else if (screenWidth < 1024) {
      iconSize = screenWidth * 0.12; // tablet: ~92px on 768px screen
    } else {
      iconSize = screenWidth * 0.072; // laptop/web: ~92px on 1280px screen
    }
    final iconPadding = iconSize * 0.28;

    // Total content height for wave-center calculation:
    //   icon container  = iconSize + iconPadding*2
    //   gap             = 28
    //   ACADIFY text    ≈ 43 px
    //   gap             =  8 px
    //   subtitle        ≈ 17 px
    final iconContainerSize = iconSize + iconPadding * 2;
    final totalHeight = iconContainerSize + 28 + 43 + 8 + 17;
    final waveCenterX = screenWidth / 2;
    final waveCenterY =
        screenHeight / 2 - totalHeight / 2 + iconContainerSize / 2;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF4A0080),
                  Color(0xFF9C27B0),
                  Color(0xFFCE93D8),
                  Color(0xFF9C27B0),
                  Color(0xFF4A0080),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CustomPaint(
              painter: _WavePainter(
                _waveController.value,
                centerX: waveCenterX,
                centerY: waveCenterY,
              ),
              child: child,
            ),
          );
        },
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon with glow — wave rings radiate from this widget's center
                Container(
                  padding: EdgeInsets.all(iconPadding),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.school,
                    size: iconSize,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'ACADIFY',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your Smart Study Platform',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double animValue;
  final double centerX;
  final double centerY;

  _WavePainter(this.animValue, {required this.centerX, required this.centerY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final cx = centerX;
    final cy = centerY;

    for (int i = 0; i < 30; i++) {
      final radius = 40.0 + i * 28.0;
      final opacity = (1.0 - i / 30) * 0.35;
      paint.color = Colors.white.withValues(alpha: opacity);

      final path = Path();
      for (double angle = 0; angle <= 2 * pi; angle += 0.02) {
        final wave = 12 * sin(6 * angle + animValue * 2 * pi + i * 0.3);
        final r = radius + wave;
        final x = cx + r * cos(angle);
        final y = cy + r * sin(angle);
        if (angle == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.animValue != animValue ||
      old.centerX != centerX ||
      old.centerY != centerY;
}
