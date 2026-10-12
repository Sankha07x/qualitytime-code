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
    await p.save();
    FxBridge.applyVideo();
    FxBridge.applyAudio();
    if (mounted) setState(() {});
  }

  Widget _bgTile(String title, String sub, BgMode m) {
    final p = _p!;
    return ListTile(
      title: Text(title),
      subtitle: Text(sub),
      selected: p.bg == m,
      trailing: p.bg == m ? const Icon(Icons.check_circle) : null,
      onTap: () {
        p.bg = m;
        _changed();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const Text('Call effects')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'All effects are off by default. Turn them on only if your '
                    'phone is fast. Video effects lower the video to about 360p '
                    'to stay smooth. If a phone cannot keep up, the effects '
                    'switch off by themselves.',
                  ),
                ),
                const ListTile(
                  title: Text('Video background',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                _bgTile('Off', 'Normal camera', BgMode.off),
                _bgTile('Blur background', 'Keeps you sharp', BgMode.blur),
                _bgTile('My wallpaper as background',
                    'Uses the wallpaper from Customize', BgMode.wallpaper),
                SwitchListTile(
                  title: const Text('Camera denoise'),
                  subtitle: const Text('Less grain in dark rooms'),
                  value: p.denoise,
                  onChanged: (v) {
                    p.denoise = v;
                    _changed();
                  },
                ),
                SwitchListTile(
                  title: const Text('Fast mode for video effects'),
                  subtitle: const Text('Lower quality, easier on cheap phones'),
                  value: p.fast,
                  onChanged: (v) {
                    p.fast = v;
                    _changed();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Noise removal (AI)'),
                  subtitle: const Text('Cleans background noise from your voice'),
                  value: p.noise,
                  onChanged: (v) {
                    p.noise = v;
                    _changed();
                  },
                ),
              ],
            ),
    );
  }
}