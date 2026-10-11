import 'package:flutter/material.dart';

/// Returns the picked colour as an int, or null if closed.
Future<int?> showColourPicker(BuildContext context, int initial) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(initial: initial),
  );
}

class _PickerSheet extends StatefulWidget {
  final int initial;
  const _PickerSheet({required this.initial});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    final h = HSVColor.fromColor(Color(widget.initial));
    _hsv = h
        .withValue(h.value.clamp(0.35, 1.0).toDouble())
        .withSaturation(h.saturation.clamp(0.15, 1.0).toDouble());
  }

  Color get _color => _hsv.toColor();

  Widget _bar(
    String label,
    double value,
    double min,
    double max,
    List<Color> colors,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          SizedBox(
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 16,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 12,
                      elevation: 3,
                    ),
                  ),
                  child: Slider(
                    value: value.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _hsv.hue;
    final s = _hsv.saturation;
    final v = _hsv.value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _color.withOpacity(0.45),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _bar(
              'Colour',
              h,
              0,
              360,
              [
                for (var i = 0; i <= 6; i++)
                  HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
              ],
              (x) => setState(() => _hsv = _hsv.withHue(x)),
            ),
            _bar(
              'Softness',
              s,
              0.15,
              1,
              [
                HSVColor.fromAHSV(1, h, 0.15, v).toColor(),
                HSVColor.fromAHSV(1, h, 1, v).toColor(),
              ],
              (x) => setState(() => _hsv = _hsv.withSaturation(x)),
            ),
            _bar(
              'Brightness',
              v,
              0.35,
              1,
              [
                HSVColor.fromAHSV(1, h, s, 0.35).toColor(),
                HSVColor.fromAHSV(1, h, s, 1).toColor(),
              ],
              (x) => setState(() => _hsv = _hsv.withValue(x)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _color.value),
                child: const Text('Use this colour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}