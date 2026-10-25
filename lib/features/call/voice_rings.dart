import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';

/// Soft rings around the avatar that move with the other person's voice.
class VoiceRings extends StatefulWidget {
  final ValueListenable<double> level;
  const VoiceRings({super.key, required this.level});

  @override
  State<VoiceRings> createState() => _VoiceRingsState();
}

class _VoiceRingsState extends State<VoiceRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  double _sm = 0;
  double _target = 0;

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
    _c.addListener(_tick);
  }

  void _onLevel() {
    _target = widget.level.value;
    if (_target > 0.03 && !_c.isAnimating) _c.repeat();
  }

  void _tick() {
    _sm += (_target - _sm) * 0.2;
    if (_target <= 0.03 && _sm < 0.01) {
      _sm = 0;
      _c.stop();
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        Color.lerp(Color(AppSettings.accent.value), Colors.white, 0.5)!;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RingsPainter(_c, () => _sm, color),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final Animation<double> c;
  final double Function() level;
  final Color color;
  _RingsPainter(this.c, this.level, this.color) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final v = level();
    if (v <= 0.01) return;
    final mid = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (c.value + i / 3) % 1.0;
      final r = 72 + p * (26 + 54 * v);
      final a = ((1 - p) * (0.18 + 0.55 * v)).clamp(0.0, 1.0);
      canvas.drawCircle(
        mid,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = color.withOpacity(a),
      );
    }
    canvas.drawCircle(
      mid,
      70 + 8 * v,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withOpacity((0.25 + 0.5 * v).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => true;
}