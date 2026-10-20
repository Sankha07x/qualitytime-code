import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Edit a photo: move/zoom, rotate, flip, filters, adjustments.
/// Pops with the new picture bytes (PNG, 640x640) or null.
class PhotoEditorScreen extends StatefulWidget {
  final Uint8List bytes;
  const PhotoEditorScreen({super.key, required this.bytes});

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _Preset {
  final String name;
  final List<double> m;
  const _Preset(this.name, this.m);
}

const _identity = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

const _presets = <_Preset>[
  _Preset('Original', _identity),
  _Preset('B&W', <double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Preset('Sepia', <double>[
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Preset('Warm', <double>[
    1.1, 0, 0, 0, 10, //
    0, 1, 0, 0, 0,
    0, 0, 0.9, 0, -10,
    0, 0, 0, 1, 0,
  ]),
  _Preset('Cool', <double>[
    0.9, 0, 0, 0, -10, //
    0, 1, 0, 0, 0,
    0, 0, 1.1, 0, 10,
    0, 0, 0, 1, 0,
  ]),
  _Preset('Vivid', <double>[
    1.2, -0.1, -0.1, 0, 0, //
    -0.1, 1.2, -0.1, 0, 0,
    -0.1, -0.1, 1.2, 0, 0,
    0, 0, 0, 1, 0,
  ]),
  _Preset('Fade', <double>[
    0.9, 0, 0, 0, 25, //
    0, 0.9, 0, 0, 25,
    0, 0, 0.9, 0, 25,
    0, 0, 0, 1, 0,
  ]),
];

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _key = GlobalKey();
  final _ctrl = TransformationController();
  double _iw = 0, _ih = 0, _side = 300;
  int _q = 0;
  bool _flip = false;
  int _f = 0;
  double _bright = 0, _contrast = 1, _sat = 1;
  int _tab = 0;
  bool _busy = false;
  bool _ready = false;
  bool _center = true;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final fr = await codec.getNextFrame();
      _iw = fr.image.width.toDouble();
      _ih = fr.image.height.toDouble();
      fr.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  double get _rw => _q.isOdd ? _ih : _iw;
  double get _rh => _q.isOdd ? _iw : _ih;
  double get _k => _side / math.min(_rw, _rh);

  void _recenter() {
    final dx = (_side - _rw * _k) / 2;
    final dy = (_side - _rh * _k) / 2;
    _ctrl.value = Matrix4.translationValues(dx, dy, 0);
  }

  void _rotate(int d) {
    setState(() {
      _q = (_q + d) % 4;
      _center = true;
    });
  }

  void _reset() {
    setState(() {
      _q = 0;
      _flip = false;
      _f = 0;
      _bright = 0;
      _contrast = 1;
      _sat = 1;
      _center = true;
    });
  }

  List<double> _satM(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final sr = (1 - s) * r, sg = (1 - s) * g, sb = (1 - s) * b;
    return [
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  List<double> _cbM() {
    final t = 128 * (1 - _contrast) + _bright * 255;
    return [
      _contrast, 0, 0, 0, t, //
      0, _contrast, 0, 0, t,
      0, 0, _contrast, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  Widget _applyAll(Widget child) => ColorFiltered(
        colorFilter: ColorFilter.matrix(_cbM()),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_satM(_sat)),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(_presets[_f].m),
            child: child,
          ),
        ),
      );

  Future<void> _done() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final b = _key.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 640 / _side);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(d!.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save the edit")),
      );
    }
  }

  Widget _editor() {
    final k = _k;
    return SizedBox(
      width: _side,
      height: _side,
      child: Stack(
        children: [
          RepaintBoundary(
            key: _key,
            child: _applyAll(
              SizedBox(
                width: _side,
                height: _side,
                child: InteractiveViewer(
                  transformationController: _ctrl,
                  constrained: false,
                  minScale: 1,
                  maxScale: 6,
                  boundaryMargin: EdgeInsets.zero,
                  child: SizedBox(
                    width: _rw * k,
                    height: _rh * k,
                    child: Transform.flip(
                      flipX: _flip,
                      child: RotatedBox(
                        quarterTurns: _q,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              size: Size(_side, _side),
              painter: _CirclePainter(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() => SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _presets.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final sel = i == _f;
            return GestureDetector(
              onTap: () => setState(() => _f = i),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        width: 2,
                        color: sel
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_presets[i].m),
                          child: Image.memory(
                            widget.bytes,
                            fit: BoxFit.cover,
                            cacheWidth: 128,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_presets[i].name, style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        ),
      );

  Widget _slider(String label, double v, double min, double max,
      ValueChanged<double> on) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: v,
            min: min,
            max: max,
            onChanged: (x) => setState(() => on(x)),
          ),
        ),
      ],
    );
  }

  Widget _adjust() => SizedBox(
        height: 110,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _slider('Brightness', _bright, -0.4, 0.4, (x) => _bright = x),
              _slider('Contrast', _contrast, 0.6, 1.6, (x) => _contrast = x),
              _slider('Saturation', _sat, 0, 2, (x) => _sat = x),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    _side = MediaQuery.of(context).size.width - 32;
    if (_ready && _center) {
      _center = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recenter();
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit photo'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            IconButton(
              tooltip: 'Done',
              icon: const Icon(Icons.check),
              onPressed: _ready ? _done : null,
            ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _editor(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Rotate left',
                          icon: const Icon(Icons.rotate_left),
                          onPressed: () => _rotate(3),
                        ),
                        IconButton(
                          tooltip: 'Rotate right',
                          icon: const Icon(Icons.rotate_right),
                          onPressed: () => _rotate(1),
                        ),
                        IconButton(
                          tooltip: 'Flip',
                          icon: const Icon(Icons.flip),
                          onPressed: () => setState(() => _flip = !_flip),
                        ),
                        IconButton(
                          tooltip: 'Reset',
                          icon: const Icon(Icons.restart_alt),
                          onPressed: _reset,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('Filters'),
                          selected: _tab == 0,
                          onSelected: (_) => setState(() => _tab = 0),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text('Adjust'),
                          selected: _tab == 1,
                          onSelected: (_) => setState(() => _tab = 1),
                        ),
                      ],
                    ),
                    _tab == 0 ? _filters() : _adjust(),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Dark outside, clear round hole inside (the part that shows as the DP).
class _CirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(path, Paint()..color = Colors.black54);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}