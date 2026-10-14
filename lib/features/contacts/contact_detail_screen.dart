import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/user_avatar.dart';
import '../call/call_log/call_log_controller.dart';
import 'contact_controller.dart';
import 'contact_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/webrtc/quality_choice.dart';
import '../../utils/settings/contact_quality_prefs.dart';
import '../voice/voice_chat_screen.dart';
import '../chat/chat_screen.dart';

/// Personal page of one contact: photo, name, ID, call buttons and the
/// call history with this person.
class ContactDetailScreen extends StatefulWidget {
  final ContactModel contact;
  final ContactController contactController;
  final CallLogController log;
  final void Function(bool video) onCall;

  const ContactDetailScreen({
    super.key,
    required this.contact,
    required this.contactController,
    required this.log,
    required this.onCall,
  });

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  int _unheard = 0;
  int _unreadChat = 0;
  QualityChoice _qa = QualityChoice.auto;
  QualityChoice _qv = QualityChoice.auto;

  Future<void> _loadQuality() async {
    final q = await ContactQualityPrefs.get(widget.contact.uid);
    if (q != null && mounted) {
      setState(() {
        _qa = q.audio;
        _qv = q.video;
      });
    }
  }

  void _saveQuality() =>
      ContactQualityPrefs.set(widget.contact.uid, ContactQuality(_qa, _qv));

  Widget _qualityRow(
    String label,
    QualityChoice cur,
    ValueChanged<QualityChoice> on,
  ) {
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label)),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final q in QualityChoice.values)
                ChoiceChip(
                  label: Text(q.name[0].toUpperCase() + q.name.substring(1)),
                  selected: cur == q,
                  onSelected: (_) => on(q),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    widget.contactController.refreshProfiles();
    _loadUnheard();
    _loadQuality();
    _loadUnreadChat();
  }

  /// Voice messages from this contact that I have not played yet.
  Future<void> _loadUnheard() async {
    final me = widget.contactController.myUid;
    if (me.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('voice_messages')
          .select('id')
          .eq('from_uid', widget.contact.uid)
          .eq('to_uid', me)
          .isFilter('played_at', null);
      if (mounted) setState(() => _unheard = (rows as List).length);
    } catch (_) {}
  }

  /// Chat messages from this contact that I have not opened yet.
  Future<void> _loadUnreadChat() async {
    final me = widget.contactController.myUid;
    if (me.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('chat_messages')
          .select('id')
          .eq('from_uid', widget.contact.uid)
          .eq('to_uid', me);
      if (mounted) setState(() => _unreadChat = (rows as List).length);
    } catch (_) {}
  }

  Future<void> _openVoice(ContactModel c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceChatScreen(
          contactName: c.displayName,
          contactUid: c.uid,
          myUid: widget.contactController.myUid,
          photoUrl: widget.contactController.photos.value[c.uid],
        ),
      ),
    );
    _loadUnheard();
  }

  Future<void> _openChat(ContactModel c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: c.displayName,
          contactUid: c.uid,
          myUid: widget.contactController.myUid,
          photoUrl: widget.contactController.photos.value[c.uid],
        ),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _when(DateTime t) {
    final now = DateTime.now();
    final hm = '${_two(t.hour)}:${_two(t.minute)}';
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return today ? 'Today $hm' : '${_two(t.day)}/${_two(t.month)}/${t.year} $hm';
  }

  String _label(CallLogEntry e) {
    switch (e.result) {
      case CallResult.answered:
        return e.outgoing ? 'Outgoing call' : 'Incoming call';
      case CallResult.missed:
        return 'Missed call';
      case CallResult.declined:
        return e.outgoing ? 'Declined by them' : 'You declined';
      case CallResult.cancelled:
        return e.outgoing ? 'No answer' : 'Cancelled';
    }
  }

  String _detail(CallLogEntry e) {
    if (e.result != CallResult.answered) return _when(e.time);
    final m = e.seconds ~/ 60;
    final s = e.seconds % 60;
    return '${_when(e.time)} · $m:${_two(s)}';
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

  Future<void> _remove(ContactModel c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('${c.displayName} will be removed from your contacts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.contactController.removeContact(c.uid);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final c = widget.contactController.contacts.value
                  .where((x) => x.uid == widget.contact.uid)
                  .firstOrNull ??
              widget.contact;
          await _openChat(c);
          _loadUnreadChat();
          _loadUnheard();
        },
        icon: Badge(
          isLabelVisible: _unreadChat + _unheard > 0,
          label: Text('${_unreadChat + _unheard}'),
          child: const Icon(Icons.chat_bubble_outline),
        ),
        label: const Text('Chat'),
      ),
      appBar: AppBar(
        title: const Text('Contact'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_remove, color: Colors.redAccent),
            tooltip: 'Remove contact',
            onPressed: () => _remove(
              widget.contactController.contacts.value
                      .where((x) => x.uid == widget.contact.uid)
                      .firstOrNull ??
                  widget.contact,
            ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<ContactModel>>(
        valueListenable: widget.contactController.contacts,
        builder: (context, list, _) {
          final c = list
                  .where((x) => x.uid == widget.contact.uid)
                  .firstOrNull ??
              widget.contact;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              Center(
                child: ValueListenableBuilder<Map<String, String>>(
                  valueListenable: widget.contactController.photos,
                  builder: (context, photos, _) => UserAvatar(
                    name: c.displayName,
                    photoUrl: photos[c.uid],
                    radius: 54,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  c.displayName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SelectableText(c.uid),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: c.uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ID copied')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => widget.onCall(false),
                      icon: const Icon(Icons.call),
                      label: const Text('Voice'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => widget.onCall(true),
                      icon: const Icon(Icons.videocam),
                      label: const Text('Video'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 20),
              Text(
                'Call quality with ${c.displayName}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Every call with this friend starts at these levels.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              _qualityRow('Audio', _qa, (v) {
                setState(() => _qa = v);
                _saveQuality();
              }),
              const SizedBox(height: 8),
              _qualityRow('Video', _qv, (v) {
                setState(() => _qv = v);
                _saveQuality();
              }),
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: widget.log.entries,
                builder: (context, _) {
                  final items = widget.log.entries.value
                      .where((e) => e.uid == c.uid)
                      .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Call history (${items.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No calls with this contact yet.'),
                        ),
                      for (final e in items)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(_icon(e), color: _color(e)),
                          title: Text(_label(e)),
                          subtitle: Text(_detail(e)),
                          trailing: Icon(
                            e.video ? Icons.videocam : Icons.call,
                            size: 18,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}