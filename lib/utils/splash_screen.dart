import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Opening animation drawn with code. Calls [onDone] when finished
/// (or when the user taps to skip).
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

double _seg(double t, double a, double b, [Curve curve = Curves.linear]) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return curve.transform((t - a) / (b - a));
}

double _o(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s =
        (MediaQuery.of(context).size.shortestSide / 390).clamp(0.8, 1.3).toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: const Color(0xFF042F2E),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final logoIn = _seg(t, 0.30, 0.65, Curves.easeOutBack);
            final fade = _o(_seg(t, 0.30, 0.50, Curves.easeOut));
            final textIn = _o(_seg(t, 0.62, 0.85, Curves.easeOut));
            final out = _o(1 - _seg(t, 0.93, 1.0));
            return Opacity(
              opacity: out,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _SplashPainter(t, s)),
                  Center(
                    child: Opacity(
                      opacity: fade,
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * logoIn,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28 * s),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 120 * s,
                            height: 120 * s,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.call,
                              size: 80 * s,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.42),
                    child: Opacity(
                      opacity: textIn,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - textIn)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'QualityTime',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26 * s,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 4,
                              ),
                            ),
                            SizedBox(height: 8 * s),
                            Text(
                              'High quality. Low bandwidth.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 13 * s,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double t;
  final double s;
  _SplashPainter(this.t, this.s);

  static const _teal = Color(0xFF14B8A6);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final m = math.min(size.width, size.height);

    // background glow
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0B4F4B), Color(0xFF042F2E)],
        ).createShader(Rect.fromCircle(center: c, radius: m * 0.95)),
    );

    // two lights slide in and meet in the middle
    Offset pos(double pp, int side) => Offset(
          c.dx + side * (1 - pp) * size.width * 0.58,
          c.dy + side * math.sin(pp * math.pi) * 40 * s,
        );
    final p = _seg(t, 0.0, 0.34, Curves.easeInOutCubic);
    final vis = 1 - _seg(t, 0.34, 0.42);
    if (vis > 0) {
      for (final side in [-1, 1]) {
        for (var i = 0; i < 14; i++) {
          final pp = p - i * 0.022;
          if (pp < 0) break;
          canvas.drawCircle(
            pos(pp, side),
            (5.5 - i * 0.3) * s,
            Paint()..color = _teal.withOpacity(_o((1 - i / 14) * 0.55 * vis)),
          );
        }
        canvas.drawCircle(
          pos(p, side),
          6 * s,
          Paint()
            ..color = Colors.white.withOpacity(_o(vis))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }

    // ripples after they meet
    for (var i = 0; i < 3; i++) {
      final start = 0.34 + i * 0.09;
      final k = _seg(t, start, start + 0.5, Curves.easeOut);
      if (k <= 0 || k >= 1) continue;
      canvas.drawCircle(
        c,
        m * 0.14 + k * m * 0.62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (2.5 * (1 - k) + 0.8) * s
          ..color = _teal.withOpacity(_o((1 - k) * 0.55)),
      );
    }

    // glow behind the logo
    final reveal = _seg(t, 0.30, 0.70, Curves.easeOut);
    if (reveal > 0) {
      final pulse = 0.9 + 0.1 * math.sin(t * math.pi * 6);
      final r = 150 * s * pulse;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            _teal.withOpacity(_o(reveal * 0.38)),
            _teal.withOpacity(0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // orbiting particles
    final pr = _seg(t, 0.38, 0.75, Curves.easeOut);
    if (pr > 0) {
      for (var i = 0; i < 16; i++) {
        final dir = i.isEven ? 1 : -1;
        final ang = i / 16 * 2 * math.pi + t * 2 * math.pi * 0.6 * dir;
        final rad = (96 + 18 * (i % 4)) * s * pr;
        final o = Offset(
          c.dx + math.cos(ang) * rad,
          c.dy + math.sin(ang) * rad,
        );
        canvas.drawCircle(
          o,
          (1.6 + (i % 3) * 0.8) * s,
          Paint()..color = Colors.white.withOpacity(_o(pr * (0.3 + 0.2 * (i % 3)))),
        );
      }
    }

    // thin progress ring around the logo
    final prog = _seg(t, 0.45, 0.9, Curves.easeInOut);
    if (prog > 0) {
      final rect = Rect.fromCircle(center: c, radius: 84 * s);
      canvas.drawCircle(
        c,
        84 * s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..color = Colors.white.withOpacity(0.10),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * prog,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3 * s
          ..color = _teal,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) => old.t != t;
}