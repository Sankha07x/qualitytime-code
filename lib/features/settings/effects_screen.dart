import 'package:flutter/material.dart';
import '../../core/webrtc/fx_bridge.dart';
import '../../utils/settings/fx_prefs.dart';

class EffectsScreen extends StatefulWidget {
  const EffectsScreen({super.key});

  @override
  State<EffectsScreen> createState() => _EffectsScreenState();
}

class _EffectsScreenState extends State<EffectsScreen> {
  FxPrefs? _p;

  @override
  void initState() {
    super.initState();
    FxPrefs.load().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  Future<void> _changed() async {
    final p = _p;
    if (p == null) return;
    try {
      await p.save();
    } catch (_) {}
    FxBridge.applyVideo();
    FxBridge.applyAudio();
    if (mounted) setState(() {});
  }

  Widget _label(String t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        t,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: cs.primary, fontWeight: FontWeight.w700, letterSpacing: 1.2),
      ),
    );
  }

  Widget _group(List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _bgTile(IconData icon, String title, String sub, BgMode m) {
    final p = _p!;
    final cs = Theme.of(context).colorScheme;
    final on = p.bg == m;
    return ListTile(
      leading: Icon(icon, color: on ? cs.primary : cs.onSurfaceVariant),
      title: Text(title,
          style: TextStyle(fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
      subtitle: Text(sub),
      trailing: on ? Icon(Icons.check_circle, color: cs.primary) : null,
      onTap: () {
        p.bg = m;
        _changed();
      },
    );
  }

  Widget _switch(IconData icon, String title, String sub, bool v,
      void Function(bool) set) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: Icon(icon, color: cs.onSurfaceVariant),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(sub),
      value: v,
      onChanged: (x) {
        set(x);
        _changed();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Call effects'), centerTitle: false),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'All effects are off by default. Turn them on only if '
                          'your phone is fast. Video effects lower the video to '
                          'about 360p to stay smooth. If a phone cannot keep up, '
                          'the effects switch off by themselves.',
                          style: TextStyle(fontSize: 13.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                _label('VIDEO BACKGROUND'),
                _group([
                  _bgTile(Icons.videocam_outlined, 'Off', 'Normal camera',
                      BgMode.off),
                  _bgTile(Icons.blur_on, 'Blur background', 'Keeps you sharp',
                      BgMode.blur),
                  _bgTile(Icons.wallpaper, 'My wallpaper as background',
                      'Uses the wallpaper from App customization',
                      BgMode.wallpaper),
                ]),
                _label('VIDEO QUALITY'),
                _group([
                  _switch(Icons.grain, 'Camera denoise',
                      'Less grain in dark rooms', p.denoise,
                      (v) => p.denoise = v),
                  _switch(Icons.speed, 'Fast mode for video effects',
                      'Lower quality, easier on cheap phones', p.fast,
                      (v) => p.fast = v),
                ]),
                _label('AUDIO'),
                _group([
                  _switch(Icons.graphic_eq, 'Noise removal (AI)',
                      'Cleans background noise from your voice', p.noise,
                      (v) => p.noise = v),
                ]),
              ],
            ),
    );
  }
}