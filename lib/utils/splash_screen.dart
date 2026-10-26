import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Opening animation: two people connect through the logo's dots,
/// talk, and the line becomes the app name.
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
    // Total time of the whole animation. Make it smaller to go faster.
    duration: const Duration(milliseconds: 3200),
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
        body: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final wf = _seg(t, 0.70, 0.78, Curves.easeOutCubic);
              final hf = _seg(t, 0.73, 0.80, Curves.easeOutCubic);
              final tag = _seg(t, 0.78, 0.86);
              final out = _o(1 - _seg(t, 0.97, 1.0));
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
                    Positioned(
                      left: 0,
                      right: 0,
                      top: box.maxHeight / 2 + 30 * s,
                      child: Opacity(
                        opacity: tag,
                        child: Text(
                          'Quality calls, valuable time',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13 * s,
                            letterSpacing: 1,
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
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double t;
  final double s;
  _SplashPainter(this.t, this.s);

  static const _teal = Color(0xFF2DD4BF);

  Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = w
    ..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final erase = _seg(t, 0.08, 0.18, Curves.easeInOut);
    final walk = _seg(t, 0.18, 0.34, Curves.easeOut);
    final reach = _seg(t, 0.30, 0.38);
    final expand = _seg(t, 0.34, 0.45, Curves.easeInOutCubic);
    final ear = _seg(t, 0.45, 0.52, Curves.easeInOut);
    final back = _seg(t, 0.62, 0.72, Curves.easeInOut);
    final fig = 1 - _seg(t, 0.60, 0.70);
    final lineA = 1 - _seg(t, 0.72, 0.80);
    final talk = _seg(t, 0.50, 0.54) * (1 - _seg(t, 0.60, 0.64));
    final up = ear * (1 - back);

    // outer ring disappears
    if (erase < 1) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 56 * s),
        -math.pi / 2,
        2 * math.pi * (1 - erase),
        false,
        _stroke(_teal, 4 * s),
      );
    }

    // the connection: dot - wave - dot
    final dotX = (27 + 93 * expand) * s + 22 * s * up;
    final dotY = c.dy - 22 * s * up;
    final half = 14 * s + (dotX - 20 * s) * expand;
    final amp = (5 + 5 * expand) * s * (1 - back);
    final dip = 16 * s * up;
    final path = Path();
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final x = c.dx - half + u * 2 * half;
      final y = dotY +
          amp * math.sin(u * 2 * math.pi) +
          dip * math.sin(u * math.pi);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, _stroke(_teal.withOpacity(_o(lineA)), 4 * s));
    final dotPaint = Paint()..color = _teal;
    canvas.drawCircle(Offset(c.dx - dotX, dotY), 5.5 * s, dotPaint);
    canvas.drawCircle(Offset(c.dx + dotX, dotY), 5.5 * s, dotPaint);

    // the two people
    if (fig > 0) {
      final edge = size.width / 2 + 30 * s;
      final stand = 152 * s;
      final dist = edge + (stand - edge) * walk;
      _man(canvas, c.dy, c.dx - dist, 1, Offset(c.dx - dotX, dotY), walk,
          reach, talk, fig);
      _man(canvas, c.dy, c.dx + dist, -1, Offset(c.dx + dotX, dotY), walk,
          reach, talk, fig);
    }
  }

  void _man(Canvas canvas, double cy, double x, double dir, Offset dot,
      double walk, double reach, double talk, double a) {
    final p = _stroke(Colors.white.withOpacity(_o(a * 0.92)), 2.4 * s);
    final hy = cy - 22 * s;
    canvas.drawCircle(Offset(x, hy), 7 * s, p);
    canvas.drawLine(Offset(x, cy - 15 * s), Offset(x, cy + 8 * s), p);
    final sw = walk < 1 ? math.sin(t * 110) * 9 * s : 0.0;
    canvas.drawLine(
        Offset(x, cy + 8 * s), Offset(x - 4 * s + sw, cy + 30 * s), p);
    canvas.drawLine(
        Offset(x, cy + 8 * s), Offset(x + 4 * s - sw, cy + 30 * s), p);
    final sh = Offset(x, cy - 12 * s);
    canvas.drawLine(sh, Offset(x - dir * 9 * s, cy + 2 * s), p);
    final hang = Offset(x + dir * 7 * s, cy + 4 * s);
    var tgt = Offset.lerp(hang, dot, reach)!;
    final v = tgt - sh;
    final d = v.distance;
    if (d > 36 * s) tgt = sh + v / d * (36 * s);
    canvas.drawLine(sh, tgt, p);

    // sound waves while talking
    if (talk > 0) {
      final base = dir > 0 ? 0.0 : math.pi;
      final k = 0.5 + 0.5 * math.sin(t * 140);
      for (var i = 0; i < 2; i++) {
        final al = _o(talk * (i == 0 ? k : 1 - k) * 0.9);
        canvas.drawArc(
          Rect.fromCircle(
              center: Offset(x + dir * 14 * s, hy), radius: (10 + i * 6) * s),
          base - 0.8,
          1.6,
          false,
          _stroke(_teal.withOpacity(al), 2 * s),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) => old.t != t;
}