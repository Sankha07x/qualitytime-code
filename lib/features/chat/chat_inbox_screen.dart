import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/user_avatar.dart';
import '../contacts/contact_controller.dart';
import '../contacts/contact_model.dart';
import 'chat_screen.dart';

class _Conv {
  final ContactModel contact;
  final DateTime at;
  final String preview;
  final int unread;
  _Conv(this.contact, this.at, this.preview, this.unread);
}

/// All chats in one list, newest message on top (like Instagram).
class ChatInboxScreen extends StatefulWidget {
  final ContactController contactController;
  final String myUid;

  const ChatInboxScreen({
    super.key,
    required this.contactController,
    required this.myUid,
  });

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  List<_Conv> _list = [];
  bool _loading = true;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    widget.contactController.contacts.addListener(_onContacts);
    _ch = Supabase.instance.client
        .channel('chat_inbox')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'voice_messages',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    widget.contactController.contacts.removeListener(_onContacts);
    _deb?.cancel();
    _ch?.unsubscribe();
    super.dispose();
  }

  void _onContacts() => _load();

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  String _two(int n) => n.toString().padLeft(2, '0');

  String _when(DateTime t) {
    final now = DateTime.now();
    final today =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return today
        ? '${_two(t.hour)}:${_two(t.minute)}'
        : '${_two(t.day)}/${_two(t.month)}';
  }

  Timer? _deb;
  bool _running = false;
  bool _again = false;

  void _load() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () async {
      if (_running) {
        _again = true;
        return;
      }
      _running = true;
      try {
        await _loadNow();
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
      _running = false;
      if (_again && mounted) {
        _again = false;
        _load();
      }
    });
  }

  Future<void> _loadNow() async {
    final me = widget.myUid;
    final db = Supabase.instance.client;
    final contacts = widget.contactController.contacts.value;

    // text and files waiting in the cloud for me
    final unreadChat = <String, int>{};
    final cloudAt = <String, DateTime>{};
    final cloudText = <String, String>{};
    try {
      final rows = await db
          .from('chat_messages')
          .select('from_uid, kind, body, created_at')
          .eq('to_uid', me)
          .neq('kind', 'delete')
          .neq('kind', 'edit')
          .isFilter('read_at', null)
          .order('created_at');
      for (final r in rows as List) {
        final u = r['from_uid'] as String;
        unreadChat[u] = (unreadChat[u] ?? 0) + 1;
        cloudAt[u] = DateTime.parse(r['created_at'] as String).toLocal();
        cloudText[u] =
            r['kind'] == 'file' ? '📎 File' : (r['body'] ?? '').toString();
      }
    } catch (_) {}

    // voice messages (both directions)
    final voiceAt = <String, DateTime>{};
    final voiceMine = <String, bool>{};
    final unheard = <String, int>{};
    try {
      final rows = await db
          .from('voice_messages')
          .select('from_uid, to_uid, created_at, played_at')
          .or('from_uid.eq.$me,to_uid.eq.$me')
          .order('created_at', ascending: false)
          .limit(300);
      for (final r in rows as List) {
        final from = r['from_uid'] as String;
        final to = r['to_uid'] as String;
        final peer = from == me ? to : from;
        if (!voiceAt.containsKey(peer)) {
          voiceAt[peer] =
              DateTime.parse(r['created_at'] as String).toLocal();
          voiceMine[peer] = from == me;
        }
        if (to == me && r['played_at'] == null) {
          unheard[peer] = (unheard[peer] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // chats saved on this phone
    final dir = await getApplicationDocumentsDirectory();
    final out = <_Conv>[];
    for (final c in contacts) {
      DateTime? at;
      var text = '';
      try {
        final f = File('${dir.path}/chat_${_safe(c.uid)}.json');
        if (await f.exists()) {
          final list = jsonDecode(await f.readAsString()) as List;
          for (final j in list) {
            final t = DateTime.parse(j['at'] as String).toLocal();
            if (at == null || t.isAfter(at)) {
              at = t;
              final body = j['kind'] == 'file'
                  ? '📎 ${j['fileName'] ?? 'File'}'
                  : (j['body'] ?? '').toString();
              text = j['from'] == me ? 'You: $body' : body;
            }
          }
        }
      } catch (_) {}
      final ca = cloudAt[c.uid];
      if (ca != null && (at == null || ca.isAfter(at))) {
        at = ca;
        text = cloudText[c.uid] ?? '';
      }
      final va = voiceAt[c.uid];
      if (va != null && (at == null || va.isAfter(at))) {
        at = va;
        text = voiceMine[c.uid] == true
            ? 'You: 🎤 Voice message'
            : '🎤 Voice message';
      }
      if (at == null) continue;
      out.add(_Conv(c, at, text,
          (unreadChat[c.uid] ?? 0) + (unheard[c.uid] ?? 0)));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      _list = out;
      _loading = false;
    });
  }

  Future<void> _open(_Conv v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactName: v.contact.displayName,
          contactUid: v.contact.uid,
          myUid: widget.myUid,
          photoUrl: widget.contactController.photos.value[v.contact.uid],
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cc = widget.contactController;
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No chats yet. Open a friend and say hi.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : AnimatedBuilder(
                  animation: cc.photos,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.all(12),
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: _list.length,
                    itemBuilder: (context, i) {
                      final v = _list[i];
                      final bold = v.unread > 0;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: bold
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black12,
                          ),
                        ),
                        tileColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(bold ? 0.12 : 0.05),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        leading: UserAvatar(
                          name: v.contact.displayName,
                          photoUrl: cc.photos.value[v.contact.uid],
                        ),
                        title: Text(
                          v.contact.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                bold ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          v.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                bold ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_when(v.at),
                                style: const TextStyle(fontSize: 12)),
                            if (bold) ...[
                              const SizedBox(height: 4),
                              Badge(label: Text('${v.unread}')),
                            ],
                          ],
                        ),
                        onTap: () => _open(v),
                      );
                    },
                  ),
                ),
    );
  }
}