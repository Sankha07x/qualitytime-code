import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'call_log_controller.dart';
import '../../../utils/user_avatar.dart';
import '../../../utils/glass.dart';

/// Floating "Recent calls" panel near the bottom of the contacts screen.
/// It hovers (gentle up-and-down) while closed, and slides open on tap.
class CallLogPanel extends StatefulWidget {
  final CallLogController log;

  /// Extra thing to listen to (e.g. the contacts list) so "Add" buttons update.
  final Listenable? refresh;

  final String Function(String uid) nameFor;
  final bool Function(String uid) isSaved;
  final void Function(String uid) onAdd;
  final void Function(CallLogEntry entry) onCallBack;
  final ValueListenable<Map<String, String>>? photos;
  final Future<String?> Function(String uid)? fetchPhoto;

  const CallLogPanel({
    super.key,
    required this.log,
    required this.nameFor,
    required this.isSaved,
    required this.onAdd,
    required this.onCallBack,
    this.refresh,
    this.photos,
    this.fetchPhoto,
  });

  @override
  State<CallLogPanel> createState() => _CallLogPanelState();
}

class _CallLogPanelState extends State<CallLogPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  bool _open = false;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _when(DateTime t) {
    final now = DateTime.now();
    final hm = '${_two(t.hour)}:${_two(t.minute)}';
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return today ? 'Today $hm' : '${_two(t.day)}/${_two(t.month)} $hm';
  }

  String _detail(CallLogEntry e) {
    switch (e.result) {
      case CallResult.answered:
        final m = e.seconds ~/ 60;
        final s = e.seconds % 60;
        return '${e.video ? 'Video' : 'Voice'} · $m:${_two(s)}';
      case CallResult.missed:
        return 'Missed';
      case CallResult.declined:
        return 'Declined';
      case CallResult.cancelled:
        return e.outgoing ? 'No answer' : 'Cancelled';
    }
  }

  IconData _icon(CallLogEntry e) {
    if (e.result == CallResult.missed) return Icons.call_missed;
    return e.outgoing ? Icons.call_made : Icons.call_received;
  }

  Color _color(CallLogEntry e) {
    switch (e.result) {
      case CallResult.answered:
        return Colors.green;
      case CallResult.missed:
      case CallResult.declined:
        return Colors.red;
      case CallResult.cancelled:
        return Colors.grey;
    }
  }

  Widget _avatar(String uid) {
    final photos = widget.photos?.value;
    if (photos != null && !photos.containsKey(uid)) {
      widget.fetchPhoto?.call(uid);
    }
    return UserAvatar(
      name: widget.nameFor(uid),
      photoUrl: photos?[uid],
      radius: 18,
    );
  }

  Widget _list() {
    final refresh = widget.refresh;
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.log.entries,
        if (refresh != null) refresh,
        if (widget.photos != null) widget.photos!,
      ]),
      builder: (context, _) {
        final items = widget.log.entries.value;
        if (items.isEmpty) {
          return const Center(child: Text('No calls yet'));
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, i) {
            final e = items[i];
            return ListTile(
              dense: true,
              leading: _avatar(e.uid),
              title: Row(
                children: [
                  Icon(_icon(e), color: _color(e), size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.nameFor(e.uid),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text('${_when(e.time)} · ${_detail(e)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.isSaved(e.uid))
                    IconButton(
                      icon: const Icon(Icons.person_add),
                      tooltip: 'Add to contacts',
                      onPressed: () => widget.onAdd(e.uid),
                    ),
                  IconButton(
                    icon: Icon(e.video ? Icons.videocam : Icons.call),
                    onPressed: () => widget.onCallBack(e),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _float,
      builder: (context, child) {
        final dy = _open ? 0.0 : -6 * Curves.easeInOut.transform(_float.value);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Glass(
        borderRadius: BorderRadius.circular(24),
        blur: 14,
        tint: scheme.surface,
        opacity: 0.55,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 12),
                      const Text(
                        'Recent calls',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: const Icon(Icons.keyboard_arrow_up),
                      ),
                    ],
                  ),
                ),
              ),
              if (_open) SizedBox(height: 300, child: _list()),
            ],
          ),
        ),
      ),
    );
  }
}
