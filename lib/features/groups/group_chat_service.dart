import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupMessage {
  final String id;
  final String fromUid;
  final String body;
  final DateTime createdAt;
  final int state; // 0 sent, 1 sending, 2 failed
  final String? replyTo;
  final String? replyText;
  final String? replyFrom;
  final DateTime? editedAt;
  const GroupMessage({
    required this.id,
    required this.fromUid,
    required this.body,
    required this.createdAt,
    this.state = 0,
    this.replyTo,
    this.replyText,
    this.replyFrom,
    this.editedAt,
  });

  bool get local => id.startsWith('local_');

  GroupMessage withBody(String b, DateTime at) => GroupMessage(
      id: id,
      fromUid: fromUid,
      body: b,
      createdAt: createdAt,
      state: state,
      replyTo: replyTo,
      replyText: replyText,
      replyFrom: replyFrom,
      editedAt: at);

  static String snip(GroupMessage m) {
    final t = m.body.replaceAll('\n', ' ');
    return t.length > 80 ? '${t.substring(0, 80)}…' : t;
  }

  GroupMessage withState(int s) => GroupMessage(
      id: id,
      fromUid: fromUid,
      body: body,
      createdAt: createdAt,
      state: s,
      replyTo: replyTo,
      replyText: replyText,
      replyFrom: replyFrom,
      editedAt: editedAt);

  factory GroupMessage.fromRow(Map<String, dynamic> r) => GroupMessage(
        id: r['id'].toString(),
        fromUid: (r['from_uid'] ?? '').toString(),
        body: (r['body'] ?? '').toString(),
        createdAt: DateTime.parse(r['created_at'].toString()).toLocal(),
        replyTo: r['reply_to']?.toString(),
        replyText: r['reply_text']?.toString(),
        replyFrom: r['reply_from']?.toString(),
        editedAt: r['edited_at'] == null
            ? null
            : DateTime.parse(r['edited_at'].toString()).toLocal(),
      );
}

/// Group chat: messages live in Supabase, every member reads the same list.
class GroupChatService {
  static const maxLen = 4000;

  final String groupId;
  final String myUid;
  final SupabaseClient _c = Supabase.instance.client;
  final messages = ValueNotifier<List<GroupMessage>>([]);
  final loading = ValueNotifier<bool>(true);
  final loadError = ValueNotifier<String?>(null);
  RealtimeChannel? _ch;
  bool _disposed = false;
  bool _loadingNow = false;
  bool _subscribedOnce = false;

  GroupChatService({required this.groupId, required this.myUid});

  List<GroupMessage> _sorted(List<GroupMessage> l) =>
      l..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> start() async {
    await load();
    if (_disposed) return;
    _ch = _c
        .channel('gchat:$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (p) => _onInsert(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'group_messages',
          callback: (p) {
            final id = p.oldRecord['id']?.toString();
            if (id != null) _remove(id);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (p) => _onUpdate(p.newRecord),
        )
        .subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (_subscribedOnce) load(); // reconnected: catch up
        _subscribedOnce = true;
      }
    });
  }

  void _onInsert(Map<String, dynamic> r) {
    if (_disposed) return;
    try {
      _put(GroupMessage.fromRow(r));
    } catch (e) {
      debugPrint('GCHAT insert parse failed: $e');
    }
  }

  void _put(GroupMessage m) {
    if (_disposed || messages.value.any((x) => x.id == m.id)) return;
    messages.value = _sorted([...messages.value, m]);
  }

  void _onUpdate(Map<String, dynamic> r) {
    if (_disposed) return;
    try {
      final u = GroupMessage.fromRow(r);
      messages.value = [
        for (final m in messages.value) m.id == u.id ? u : m,
      ];
    } catch (e) {
      debugPrint('GCHAT update parse failed: $e');
    }
  }

  void _remove(String id) {
    if (_disposed) return;
    messages.value = [for (final m in messages.value) if (m.id != id) m];
  }

  void _setState(String id, int s) {
    if (_disposed) return;
    messages.value = [
      for (final m in messages.value) m.id == id ? m.withState(s) : m,
    ];
  }

  Future<void> retryLoad() async {
    loadError.value = null;
    loading.value = true;
    await load();
  }

  Future<void> load() async {
    if (_disposed || _loadingNow) return;
    _loadingNow = true;
    try {
      final rows = await _c
          .from('group_messages')
          .select(
              'id, from_uid, body, created_at, reply_to, reply_text, reply_from, edited_at')
          .eq('group_id', groupId)
          .order('created_at', ascending: false)
          .limit(300);
      final server = [
        for (final r in rows as List)
          GroupMessage.fromRow(Map<String, dynamic>.from(r)),
      ];
      final keep = messages.value.where((m) => m.local).toList();
      if (_disposed) return;
      messages.value = _sorted([...server, ...keep]);
      loadError.value = null;
    } catch (e) {
      debugPrint('GCHAT load failed: $e');
      if (!_disposed && messages.value.isEmpty) {
        loadError.value = 'Could not load messages. Check your internet.';
      }
    } finally {
      _loadingNow = false;
      if (!_disposed) loading.value = false;
    }
  }

  /// Returns a short text to show the user, or null when all is fine.
  Future<String?> send(String text,
      {String? retryId, GroupMessage? replyTo}) async {
    final t = text.trim();
    if (t.isEmpty) return 'Nothing to send.';
    if (t.length > maxLen) return 'Message is too long.';
    final localId =
        retryId ?? 'local_${DateTime.now().microsecondsSinceEpoch}';
    final prev = messages.value.where((x) => x.id == retryId).firstOrNull;
    final rId = replyTo?.id ?? prev?.replyTo;
    final rText = replyTo != null ? GroupMessage.snip(replyTo) : prev?.replyText;
    final rFrom = replyTo?.fromUid ?? prev?.replyFrom;
    if (retryId == null) {
      _put(GroupMessage(
        id: localId,
        fromUid: myUid,
        body: t,
        createdAt: DateTime.now(),
        state: 1,
        replyTo: rId,
        replyText: rText,
        replyFrom: rFrom,
      ));
    } else {
      _setState(localId, 1);
    }
    try {
      final row = await _c
          .from('group_messages')
          .insert({
            'group_id': groupId,
            'from_uid': myUid,
            'body': t,
            if (rId != null) 'reply_to': rId,
            if (rText != null) 'reply_text': rText,
            if (rFrom != null) 'reply_from': rFrom,
          })
          .select('id, created_at')
          .single()
          .timeout(const Duration(seconds: 20));
      if (_disposed) return null;
      final real = GroupMessage(
        id: row['id'].toString(),
        fromUid: myUid,
        body: t,
        createdAt: DateTime.parse(row['created_at'].toString()).toLocal(),
        replyTo: rId,
        replyText: rText,
        replyFrom: rFrom,
      );
      messages.value = _sorted([
        for (final m in messages.value)
          if (m.id != localId && m.id != real.id) m,
        real,
      ]);
      return null;
    } on PostgrestException catch (e) {
      debugPrint('GCHAT send failed: ${e.code} ${e.message}');
      if (e.code == '42501') {
        _remove(localId);
        return 'You are not in this group anymore.';
      }
      _setState(localId, 2);
      return 'Could not send. Tap the message to retry.';
    } catch (e) {
      debugPrint('GCHAT send failed: $e');
      _setState(localId, 2);
      return 'No connection. Tap the message to retry.';
    }
  }

  static const editWindow = Duration(minutes: 15);

  bool canEdit(GroupMessage m) =>
      !m.local &&
      m.state == 0 &&
      m.fromUid == myUid &&
      DateTime.now().difference(m.createdAt) < editWindow;

  /// Returns an error text, or null on success.
  Future<String?> editText(GroupMessage m, String text) async {
    final t = text.trim();
    if (t.isEmpty) return 'Message cannot be empty.';
    if (t.length > maxLen) return 'Message is too long.';
    if (!canEdit(m)) return 'You can only edit within 15 minutes.';
    if (t == m.body) return null;
    try {
      await _c
          .from('group_messages')
          .update({'body': t})
          .eq('id', m.id)
          .eq('from_uid', myUid)
          .select('id')
          .single()
          .timeout(const Duration(seconds: 20));
      if (!_disposed) {
        messages.value = [
          for (final x in messages.value)
            x.id == m.id ? x.withBody(t, DateTime.now()) : x,
        ];
      }
      return null;
    } on PostgrestException catch (e) {
      debugPrint('GCHAT edit failed: ${e.code} ${e.message}');
      if (e.message.contains('edit_window')) {
        return 'You can only edit within 15 minutes.';
      }
      return 'Could not edit this message.';
    } catch (e) {
      debugPrint('GCHAT edit failed: $e');
      return 'No connection. Try again.';
    }
  }

  Future<String?> delete(GroupMessage m) async {
    if (m.local) {
      _remove(m.id);
      return null;
    }
    try {
      await _c
          .from('group_messages')
          .delete()
          .eq('id', m.id)
          .eq('from_uid', myUid);
      _remove(m.id);
      return null;
    } catch (e) {
      debugPrint('GCHAT delete failed: $e');
      return 'Could not delete. Check your internet.';
    }
  }

  void dispose() {
    _disposed = true;
    _ch?.unsubscribe();
    messages.dispose();
    loading.dispose();
    loadError.dispose();
  }
}