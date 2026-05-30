import 'dart:math' as math;

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _splashDuration = Duration(milliseconds: 4200);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slideUp;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _splashDuration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onFinished();
      }
    });
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.36, curve: Curves.easeOutCubic),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, -0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0, 0.36, curve: Curves.easeOutCubic),
          ),
        );
    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.04, 0.34, curve: Curves.easeOutCubic),
    );
    _logoSlide = Tween<Offset>(begin: const Offset(0, -0.22), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.04, 0.34, curve: Curves.easeOutCubic),
          ),
        );
    _titleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.46, curve: Curves.easeOutCubic),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, -0.18), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.18, 0.46, curve: Curves.easeOutCubic),
          ),
        );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: SizedBox.expand(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slideUp,
            child: _SplashCard(
              logoFade: _logoFade,
              logoSlide: _logoSlide,
              titleFade: _titleFade,
              titleSlide: _titleSlide,
              progress: _controller,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashCard extends StatelessWidget {
  const _SplashCard({
    required this.logoFade,
    required this.logoSlide,
    required this.titleFade,
    required this.titleSlide,
    required this.progress,
  });

  final Animation<double> logoFade;
  final Animation<Offset> logoSlide;
  final Animation<double> titleFade;
  final Animation<Offset> titleSlide;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final shortestSide = math.min(width, height);
        final logoSize = math.min(
          214.0,
          math.max(124.0, math.min(width * 0.42, height * 0.26)),
        );
        final horizontalPadding = math.max(
          22.0,
          math.min(38.0, shortestSide * 0.055),
        );
        final verticalPadding = math.max(22.0, math.min(42.0, height * 0.045));

        return Stack(
          fit: StackFit.expand,
          children: [
            const _BlueBackground(),
            const _LineWaves(),
            const Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _BuildingSilhouette(),
              ),
            ),
            SafeArea(
              minimum: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  FadeTransition(
                    opacity: logoFade,
                    child: SlideTransition(
                      position: logoSlide,
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF38A5FF,
                              ).withValues(alpha: 0.35),
                              blurRadius: 36,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(logoSize * 0.1),
                          child: Image.asset(
                            'assets/logo/gestia.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: math.max(18, height * 0.032)),
                  FadeTransition(
                    opacity: titleFade,
                    child: SlideTransition(
                      position: titleSlide,
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: RichText(
                              textAlign: TextAlign.center,
                              text: const TextSpan(
                                style: TextStyle(
                                  fontSize: 29,
                                  height: 1,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                  color: Colors.white,
                                ),
                                children: [
                                  TextSpan(text: 'RECETTES '),
                                  TextSpan(
                                    text: 'PROVINCIALES',
                                    style: TextStyle(color: Color(0xFF35C24A)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Gestion des recettes',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 28),
                          _ProgressBars(progress: progress),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 5),
                  const _SecureBadge(),
                  SizedBox(height: math.max(22, height * 0.05)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BlueBackground extends StatelessWidget {
  const _BlueBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF031B5B),
            Color(0xFF0057C8),
            Color(0xFF00338B),
            Color(0xFF000F3D),
          ],
          stops: [0, 0.36, 0.68, 1],
        ),
      ),
    );
  }
}

class _LineWaves extends StatelessWidget {
  const _LineWaves();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LineWavesPainter());
  }
}

class _LineWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bluePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF22A7FF).withValues(alpha: 0.22);
    final greenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF34C84A).withValues(alpha: 0.72);

    for (var i = 0; i < 18; i++) {
      final path = Path();
      final y = size.height * (0.18 + i * 0.012);
      path.moveTo(size.width * 0.34, y);
      path.cubicTo(
        size.width * 0.62,
        y + 90,
        size.width * 0.78,
        y - 130,
        size.width * 1.08,
        y - 30,
      );
      canvas.drawPath(path, bluePaint);
    }

    final topGreen = Path()
      ..moveTo(size.width * 0.28, size.height * 0.44)
      ..cubicTo(
        size.width * 0.5,
        size.height * 0.35,
        size.width * 0.72,
        size.height * 0.52,
        size.width * 1.04,
        size.height * 0.31,
      );
    canvas.drawPath(topGreen, greenPaint);

    for (var i = 0; i < 22; i++) {
      final path = Path();
      final startY = size.height * (0.72 + i * 0.008);
      path.moveTo(-size.width * 0.08, startY);
      path.cubicTo(
        size.width * 0.22,
        startY + 120,
        size.width * 0.7,
        startY - 80,
        size.width * 1.08,
        startY + 30,
      );
      canvas.drawPath(path, bluePaint);
    }

    final bottomGreen = Path()
      ..moveTo(size.width * 0.68, size.height * 1.02)
      ..cubicTo(
        size.width * 0.82,
        size.height * 0.94,
        size.width * 0.88,
        size.height * 0.83,
        size.width * 1.1,
        size.height * 0.78,
      );
    canvas.drawPath(bottomGreen, greenPaint);

    final dots = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    for (var row = 0; row < 18; row++) {
      for (var col = 0; col < 16; col++) {
        final x = size.width * 0.72 + col * 10.0;
        final y = 28 + row * 10.0 + math.sin(col) * 2;
        if (x < size.width && y < size.height * 0.28) {
          canvas.drawCircle(Offset(x, y), 1, dots);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BuildingSilhouette extends StatelessWidget {
  const _BuildingSilhouette();

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.38,
      widthFactor: 1,
      child: CustomPaint(painter: _BuildingPainter()),
    );
  }
}

class _BuildingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = const Color(0xFF03285F).withValues(alpha: 0.72);
    final glow = Paint()
      ..color = const Color(0xFF0A4EA8).withValues(alpha: 0.34);
    final bottom = size.height * 0.88;
    final top = size.height * 0.32;

    final body = Path()
      ..moveTo(size.width * 0.06, bottom)
      ..lineTo(size.width * 0.14, top + 42)
      ..lineTo(size.width * 0.42, top + 10)
      ..quadraticBezierTo(
        size.width * 0.5,
        top - 42,
        size.width * 0.58,
        top + 10,
      )
      ..lineTo(size.width * 0.86, top + 48)
      ..lineTo(size.width * 0.96, bottom)
      ..close();
    canvas.drawPath(body, glow);

    final roof = Path()
      ..moveTo(size.width * 0.1, top + 74)
      ..lineTo(size.width * 0.26, top + 30)
      ..lineTo(size.width * 0.43, top + 74)
      ..close();
    canvas.drawPath(roof, base);

    final dome = Rect.fromCenter(
      center: Offset(size.width * 0.5, top + 16),
      width: size.width * 0.16,
      height: size.height * 0.22,
    );
    canvas.drawArc(dome, math.pi, math.pi, true, base);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.47, top + 10, size.width * 0.06, 56),
      base,
    );

    for (var i = 0; i < 10; i++) {
      final x = size.width * (0.14 + i * 0.074);
      canvas.drawRect(Rect.fromLTWH(x, top + 92, 13, bottom - top - 118), base);
    }

    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.08, bottom - 20, size.width * 0.84, 20),
      base,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final rawValue = progress.value.clamp(0.0, 1.0).toDouble();
        final value = ((rawValue - 0.30) / 0.70).clamp(0.0, 1.0).toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Bar(color: const Color(0xFF32C653), width: 44, fill: value * 3),
            const SizedBox(width: 8),
            _Bar(
              color: const Color(0xFF6685B8),
              width: 44,
              fill: (value * 3) - 1,
            ),
            const SizedBox(width: 8),
            _Bar(
              color: const Color(0xFF4B6FA8),
              width: 44,
              fill: (value * 3) - 2,
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.width, required this.fill});

  final Color color;
  final double width;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final normalizedFill = fill.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: width,
        height: 6,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.25)),
        child: FractionallySizedBox(
          widthFactor: normalizedFill,
          alignment: Alignment.centerLeft,
          child: DecoratedBox(decoration: BoxDecoration(color: color)),
        ),
      ),
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.security_outlined,
            color: Color(0xFF35C24A),
            size: 34,
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Connexion sécurisée',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Données protégées',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
