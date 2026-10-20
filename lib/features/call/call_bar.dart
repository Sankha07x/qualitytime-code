import 'dart:async';
import 'package:flutter/material.dart';
import 'active_call.dart';
import '../../utils/glass.dart';
import '../../utils/settings/app_settings.dart';

/// Wraps the whole app: shows a green "ongoing call" bar on top of every
/// screen while a call is minimized.
class CallBarHost extends StatelessWidget {
  final Widget child;
  const CallBarHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActiveCallInfo?>(
      valueListenable: ActiveCall.current,
      builder: (context, info, _) {
        return Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: info == null
                  ? const SizedBox(width: double.infinity)
                  : _Bar(info: info),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: info != null,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatefulWidget {
  final ActiveCallInfo info;
  const _Bar({required this.info});

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _time() {
    final s = widget.info.controller.connectedSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      tint: Color(AppSettings.accent.value),
      opacity: 0.85,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: ActiveCall.returnToCall,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              children: [
                Icon(
                  widget.info.video ? Icons.videocam : Icons.call,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.info.name} · ${_time()}  ·  Tap to return',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'End call',
                  onPressed: ActiveCall.hangUp,
                  icon: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}