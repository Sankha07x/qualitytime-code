import 'package:flutter/material.dart';
import '../../core/webrtc/quality_choice.dart';
import '../../utils/settings/data_saver_prefs.dart';
import 'call_controller.dart';
import '../../utils/glass.dart';

/// Bottom sheet: audio quality, video quality, and the data-saver switch.
class QualitySheet extends StatefulWidget {
  final CallController controller;
  final bool showVideo;

  const QualitySheet({
    super.key,
    required this.controller,
    required this.showVideo,
  });

  @override
  State<QualitySheet> createState() => _QualitySheetState();
}

class _QualitySheetState extends State<QualitySheet> {
  late QualityChoice _audio;
  late QualityChoice _video;
  bool _saver = false;

  @override
  void initState() {
    super.initState();
    _audio = widget.controller.audioChoice;
    _video = widget.controller.videoChoice;
    DataSaverPrefs.isOn().then((v) {
      if (mounted) setState(() => _saver = v);
    });
  }

  String _label(QualityChoice c) {
    switch (c) {
      case QualityChoice.auto:
        return 'Auto';
      case QualityChoice.low:
        return 'Low';
      case QualityChoice.medium:
        return 'Medium';
      case QualityChoice.high:
        return 'High';
    }
  }

  Widget _choices(
    String title,
    QualityChoice selected,
    ValueChanged<QualityChoice> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final c in QualityChoice.values)
              ChoiceChip(
                label: Text(_label(c)),
                labelStyle: TextStyle(
                  color: Colors.white,
                ),
                backgroundColor: Colors.white24,
                selectedColor: Colors.blueAccent,
                showCheckmark: false,
                selected: c == selected,
                onSelected: (_) => onSelect(c),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Glass(
        margin: const EdgeInsets.all(8),
        borderRadius: BorderRadius.circular(28),
        blur: 20,
        tint: Colors.black,
        opacity: 0.45,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _choices('Audio quality', _audio, (c) {
              setState(() => _audio = c);
              widget.controller.setAudioChoice(c);
            }),
            if (widget.showVideo) ...[
              const SizedBox(height: 16),
              _choices('Video quality', _video, (c) {
                setState(() => _video = c);
                widget.controller.setVideoChoice(c);
              }),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Data saver',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Start every call on Low',
                style: TextStyle(color: Colors.white70),
              ),
              value: _saver,
              onChanged: (v) {
                setState(() => _saver = v);
                DataSaverPrefs.setOn(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}