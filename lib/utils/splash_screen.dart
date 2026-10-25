import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Opening animation: the logo ring spirals open into a line,
/// then the line opens into the app name.
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
    duration: const Duration(milliseconds: 1400),
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
    final s = (MediaQuery.of(context).size.shortestSide / 390)
        .clamp(0.8, 1.3)
        .toDouble();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: Scaffold(
        backgroundColor: const Color(0xFF042F2E),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final wf = _seg(t, 0.55, 0.74, Curves.easeOutCubic);
            final hf = _seg(t, 0.60, 0.80, Curves.easeOutCubic);
            final out = _o(1 - _seg(t, 0.92, 1.0));
            return Opacity(
              opacity: out,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _SplashPainter(t, s)),
                  Center(
                    child: ClipRect(
                      child: Align(
                        widthFactor: math.max(wf, 0.001),
                        heightFactor: math.max(hf, 0.001),
                        child: Text(
                          'QualityTime',
                          softWrap: false,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28 * s,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 3,
                          ),
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

  static const _teal = Color(0xFF2DD4BF);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = 56 * s;
    final len = math.min(size.width * 0.75, 260 * s);
    final draw = _seg(t, 0.0, 0.20, Curves.easeOut);
    final m = _seg(t, 0.22, 0.55, Curves.easeInOutCubic);
    final lineFade = 1 - _seg(t, 0.58, 0.78);

    // ring that unwinds into a line
    const n = 90;
    final count = (n * draw).ceil();
    final path = Path();
    for (var i = 0; i <= count; i++) {
      final u = i / n;
      final mi = Curves.easeInOut.transform(_o(m * 1.7 - u * 0.7));
      final ang = -math.pi / 2 + u * 0.92 * 2 * math.pi - (1 - draw) * math.pi;
      final rad = r * (1 - 0.6 * mi);
      final sp = Offset(
        c.dx + math.cos(ang + mi * math.pi * 1.2) * rad,
        c.dy + math.sin(ang + mi * math.pi * 1.2) * rad,
      );
      final lp = Offset(c.dx - len / 2 + u * len, c.dy);
      final p = Offset.lerp(sp, lp, mi)!;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 4 * s
        ..color = _teal.withOpacity(_o(lineFade)),
    );

    // wave in the middle, fades as the ring opens
    final waveA = _o(draw * (1 - _seg(t, 0.20, 0.34)));
    if (waveA > 0) {
      final w = Path()
        ..moveTo(c.dx - 14 * s, c.dy - 5 * s)
        ..cubicTo(c.dx - 4 * s, c.dy - 10 * s, c.dx - 2 * s, c.dy + 5 * s,
            c.dx + 6 * s, c.dy + 5 * s)
        ..lineTo(c.dx + 13 * s, c.dy + 5 * s);
      canvas.drawPath(
        w,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4 * s
          ..color = _teal.withOpacity(waveA),
      );
    }

    // two dots: inside the ring first, then the ends of the line
    final dm = Curves.easeInOut.transform(m);
    // dots travel with the same easing as the ring
    final dotX = 27 * s + (len / 2 - 27 * s) * dm;
    final dotR = (5.5 - 1.5 * dm) * s;
    final dotPaint = Paint()..color = _teal.withOpacity(_o(draw));
    canvas.drawCircle(Offset(c.dx - dotX, c.dy), dotR, dotPaint);
    canvas.drawCircle(Offset(c.dx + dotX, c.dy), dotR, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) => old.t != t;
}