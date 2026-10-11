import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_service.dart';

Future<bool?> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: !info.forced,
    barrierLabel: 'Update',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) => _UpdateDialog(info: info),
    transitionBuilder: (context, anim, _, child) {
      final c = anim.drive(CurveTween(curve: Curves.easeOutCubic));
      return AnimatedBuilder(
        animation: c,
        builder: (context, _) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8 * c.value, sigmaY: 8 * c.value),
          child: FadeTransition(
            opacity: c,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(c),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(c),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _Phase { idle, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  static const _teal = Color(0xFF0D9488);
  static const _tealLight = Color(0xFF5EEAD4);

  _Phase _phase = _Phase.idle;
  int _percent = 0;
  StreamSubscription<OtaEvent>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _phase = _Phase.downloading;
      _percent = 0;
    });
    _sub?.cancel();
    try {
      _sub = OtaUpdate()
          .execute(
        widget.info.apkUrl,
        destinationFilename: 'qualitytime-update.apk',
      )
          .listen((e) {
        if (!mounted) return;
        final s = e.status.name;
        if (s == 'DOWNLOADING') {
          setState(() => _percent = int.tryParse(e.value ?? '') ?? _percent);
        } else if (s == 'INSTALLING' || s == 'INSTALLATION_DONE') {
          setState(() {
            _phase = _Phase.installing;
            _percent = 100;
          });
        } else if (s.contains('ERROR') || s == 'CANCELED') {
          setState(() => _phase = _Phase.error);
        }
      }, onError: (_) {
        if (mounted) setState(() => _phase = _Phase.error);
      });
    } catch (_) {
      setState(() => _phase = _Phase.error);
    }
  }

  Future<void> _browser() async {
    try {
      await launchUrl(
        Uri.parse(widget.info.apkUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Widget _primary(String label, VoidCallback onTap) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _quiet(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }

  Widget _actions() {
    final info = widget.info;
    switch (_phase) {
      case _Phase.idle:
        return Row(
          key: const ValueKey('idle'),
          children: [
            if (!info.forced) ...[
              Expanded(
                child: _quiet('Later', () => Navigator.of(context).pop(true)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 2,
              child: _primary('Update now', _start),
            ),
          ],
        );
      case _Phase.downloading:
        return Column(
          key: const ValueKey('down'),
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: _percent / 100),
              duration: const Duration(milliseconds: 300),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                backgroundColor: Colors.white12,
                color: _tealLight,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Downloading… $_percent%',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        );
      case _Phase.installing:
        return Column(
          key: const ValueKey('inst'),
          children: [
            const Text(
              'Installer opened. Tap Install to finish.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            _quiet('Try again', _start),
          ],
        );
      case _Phase.error:
        return Column(
          key: const ValueKey('err'),
          children: [
            const Text(
              "Couldn't download the update.",
              style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _quiet('Open in browser', _browser)),
                const SizedBox(width: 8),
                Expanded(child: _primary('Retry', _start)),
              ],
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final busy =
        _phase == _Phase.downloading || _phase == _Phase.installing;
    final size = info.sizeMb != null
        ? ' · ${info.sizeMb!.toStringAsFixed(0)} MB'
        : '';
    return PopScope(
      canPop: !info.forced && !busy,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 330,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1F1E).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white12),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 40),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_tealLight, _teal],
                    ),
                    boxShadow: [
                      BoxShadow(color: Color(0x660D9488), blurRadius: 24),
                    ],
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  info.forced ? 'Update required' : 'Update available',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'QualityTime ${info.versionName}$size',
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                if (info.forced) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'This version can no longer connect. Please update to keep calling.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
                if (!busy && info.notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final n in info.notes.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6, right: 10),
                            child: CircleAvatar(
                              radius: 2.5,
                              backgroundColor: _tealLight,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              n,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _actions(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}