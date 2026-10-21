import 'dart:async';
import 'dart:io' show File;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';
import 'colour_picker_sheet.dart';
import 'effects_screen.dart';

class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key, this.callMode = false});
  final bool callMode;

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen> {
  final _player = AudioPlayer();
  Timer? _stopTimer;
  bool _busy = false;

  @override
  void dispose() {
    _stopTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _preview(String id) async {
    if (id == 'system') return;
    try {
      _stopTimer?.cancel();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.play(AppSettings.sourceFor(id), volume: 0.7);
      _stopTimer = Timer(const Duration(seconds: 4), () => _player.stop());
    } catch (_) {}
  }

  Future<void> _pickWallpaper() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final err = await AppSettings.pickWallpaper();
      if (err != null) _toast(err);
    } catch (_) {
      _toast("Couldn't set the wallpaper");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTone({required bool incoming}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final err = await AppSettings.pickCustomTone(incoming: incoming);
      if (err != null) {
        _toast(err);
      } else {
        _preview('custom');
      }
    } catch (_) {
      _toast("Couldn't use that audio file");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _holdSection() {
    final scheme = Theme.of(context).colorScheme;
    Widget check(bool on) => on
        ? Icon(Icons.check_circle, color: scheme.primary)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Hold sound (plays on your phone when someone puts you on hold)'),
        ValueListenableBuilder<String>(
          valueListenable: AppSettings.holdTone,
          builder: (context, cur, _) => Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.volume_off),
                title: const Text('No sound'),
                trailing: check(cur == 'off'),
                onTap: () => AppSettings.setHoldTone('off'),
              ),
              for (final e in AppSettings.tones.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note),
                  title: Text(e.value),
                  trailing: check(cur == e.key),
                  onTap: () {
                    AppSettings.setHoldTone(e.key);
                    _preview(e.key);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(
          t,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      );

  Widget _toneSection({
    required String title,
    required ValueNotifier<String> notifier,
    required void Function(String) onSelect,
    required bool incoming,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget check(bool on) => on
        ? Icon(Icons.check_circle, color: scheme.primary)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(title),
        ValueListenableBuilder<String>(
          valueListenable: notifier,
          builder: (context, cur, _) => Column(
            children: [
              if (incoming)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_android),
                  title: const Text('Phone default ringtone'),
                  trailing: check(cur == 'system'),
                  onTap: () => onSelect('system'),
                ),
              for (final e in AppSettings.tones.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note),
                  title: Text(e.value),
                  trailing: check(cur == e.key),
                  onTap: () {
                    onSelect(e.key);
                    _preview(e.key);
                  },
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open),
                title: const Text('My own audio'),
                subtitle: Text(
                  AppSettings.customToneName ?? 'Pick a file from your phone',
                ),
                trailing: check(cur == 'custom'),
                onTap: () {
                  if (AppSettings.customTonePath != null && cur != 'custom') {
                    onSelect('custom');
                    _preview('custom');
                  } else {
                    _pickTone(incoming: incoming);
                  }
                },
              ),
              if (cur == 'custom')
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tap "My own audio" again to pick a different file.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              if (incoming)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Your own audio plays when the app is open. When the app is closed, Android uses the phone default ringtone.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.callMode ? 'Call customization' : 'App customization'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          if (widget.callMode)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Call effects'),
              subtitle: const Text(
                'Background blur, camera denoise, noise removal. All off by default.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EffectsScreen()),
              ),
            ),
          ),
          if (!widget.callMode) _section('Accent colour'),
          if (!widget.callMode)
          ValueListenableBuilder<int>(
            valueListenable: AppSettings.accent,
            builder: (context, cur, _) {
              final custom = !AppSettings.accents.contains(cur);
              Widget dot(int c) => GestureDetector(
                    onTap: () => AppSettings.setAccent(c),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              c == cur ? scheme.onSurface : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: c == cur
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppSettings.accents) dot(c),
                  if (custom) dot(cur),
                  GestureDetector(
                    onTap: () async {
                      final c = await showColourPicker(context, cur);
                      if (c != null) AppSettings.setAccent(c);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(colors: [
                          Colors.red,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ]),
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
          if (!widget.callMode) _section('Wallpaper'),
          if (!widget.callMode)
          ValueListenableBuilder<String?>(
            valueListenable: AppSettings.wallpaper,
            builder: (context, wp, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: wp == null
                        ? Container(
                            color: scheme.surfaceContainerHighest,
                            child: const Center(child: Text('No wallpaper')),
                          )
                        : Image.file(File(wp), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _pickWallpaper,
                      child: const Text('Choose picture'),
                    ),
                    const SizedBox(width: 8),
                    if (wp != null)
                      TextButton(
                        onPressed: AppSettings.clearWallpaper,
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Stays on this phone only.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                if (wp != null) ...[
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.wallpaperOnCall,
                    builder: (context, on, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use as call background'),
                      subtitle: const Text('Shown when the camera is off'),
                      value: on,
                      onChanged: AppSettings.setWallpaperOnCall,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.wallpaperBlur,
                    builder: (context, on, _) => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Blur wallpaper'),
                      value: on,
                      onChanged: AppSettings.setWallpaperBlur,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.callMode)
          _toneSection(
            title: 'Calling tone (what you hear while calling)',
            notifier: AppSettings.tone,
            onSelect: AppSettings.setTone,
            incoming: false,
          ),
          if (widget.callMode)
          _toneSection(
            title: 'Incoming ringtone (when someone calls you)',
            notifier: AppSettings.incomingTone,
            onSelect: AppSettings.setIncomingTone,
            incoming: true,
          ),
          _holdSection(
          ),
        ],
      ),
    );
  }
}