import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  final String id;
  final String fromUid;
  final String toUid;
  final String kind; // 'text' or 'file'
  final String? body;
  final String? fileName;
  final String? localName; // file saved on this phone
  final int? fileSize;
  final DateTime createdAt;
  const ChatMessage({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.kind,
    this.body,
    this.fileName,
    this.localName,
    this.fileSize,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromUid,
        'to': toUid,
        'kind': kind,
        'body': body,
        'fileName': fileName,
        'localName': localName,
        'fileSize': fileSize,
        'at': createdAt.toUtc().toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        fromUid: j['from'] as String,
        toUid: j['to'] as String,
        kind: j['kind'] as String,
        body: j['body'] as String?,
        fileName: j['fileName'] as String?,
        localName: j['localName'] as String?,
        fileSize: (j['fileSize'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['at'] as String).toLocal(),
      );
}

/// Text and file chat with one friend. Messages wait in Supabase until the
/// receiver opens the chat. Then they are saved on the receiver's phone and
/// the cloud copy (row and file) is deleted. Both phones keep own history.
class ChatService {
  static const maxFileBytes = 3670016; // 3.5 MB
  static const bucket = 'chat-files';

  final String myUid;
  final String peerUid;
  final SupabaseClient _c = Supabase.instance.client;
  final messages = ValueNotifier<List<ChatMessage>>([]);
  RealtimeChannel? _ch;
  bool _disposed = false;
  bool _busy = false;

  ChatService({required this.myUid, required this.peerUid});

  String get _safePeer => peerUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<Directory> _dir() => getApplicationDocumentsDirectory();

  Future<File> _store() async =>
      File('${(await _dir()).path}/chat_$_safePeer.json');

  Future<void> _load() async {
    try {
      final f = await _store();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      messages.value = [
        for (final j in list) ChatMessage.fromJson(Map<String, dynamic>.from(j)),
      ];
    } catch (e) {
      debugPrint('CHAT load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final f = await _store();
      await f.writeAsString(
          jsonEncode([for (final m in messages.value) m.toJson()]),
          flush: true);
    } catch (e) {
      debugPrint('CHAT save failed: $e');
    }
  }

  Future<void> _add(ChatMessage m) async {
    if (_disposed || messages.value.any((x) => x.id == m.id)) return;
    final list = [...messages.value, m]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messages.value = list;
    await _save();
  }

  Future<void> start() async {
    await _load();
    await fetchIncoming();
    if (_disposed) return;
    _ch = _c
        .channel('chat:$myUid:$peerUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) => fetchIncoming(),
        )
        .subscribe();
  }

  /// Takes new messages from the cloud, saves them here, deletes the cloud copy.
  Future<void> fetchIncoming() async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      final rows = await _c
          .from('chat_messages')
          .select()
          .eq('from_uid', peerUid)
          .eq('to_uid', myUid)
          .order('created_at');
      for (final r in rows as List) {
        final row = Map<String, dynamic>.from(r);
        final id = row['id'] as String;
        final isFile = row['kind'] == 'file';
        final cloudPath = row['file_path'] as String?;
        String? localName;
        if (isFile && cloudPath != null) {
          try {
            final bytes = await _c.storage.from(bucket).download(cloudPath);
            localName = 'chatfile_${id}_${_safe(row['file_name'] as String? ?? 'file')}';
            await File('${(await _dir()).path}/$localName')
                .writeAsBytes(bytes, flush: true);
          } catch (e) {
            debugPrint('CHAT download failed: $e');
            continue; // try again next time
          }
        }
        await _add(ChatMessage(
          id: id,
          fromUid: peerUid,
          toUid: myUid,
          kind: row['kind'] as String,
          body: row['body'] as String?,
          fileName: row['file_name'] as String?,
          localName: localName,
          fileSize: (row['file_size'] as num?)?.toInt(),
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        ));
        try {
          if (cloudPath != null) {
            await _c.storage.from(bucket).remove([cloudPath]); // file first
          }
          await _c.from('chat_messages').delete().eq('id', id);
        } catch (e) {
          debugPrint('CHAT cloud delete failed: $e');
        }
      }
    } catch (e) {
      debugPrint('CHAT fetch failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Returns an error text, or null on success.
  Future<String?> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return 'Nothing to send.';
    if (t.length > 4000) return 'Message is too long.';
    try {
      final row = await _c
          .from('chat_messages')
          .insert({'from_uid': myUid, 'to_uid': peerUid, 'kind': 'text', 'body': t})
          .select('id, created_at')
          .single();
      await _add(ChatMessage(
        id: row['id'] as String,
        fromUid: myUid,
        toUid: peerUid,
        kind: 'text',
        body: t,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      ));
      return null;
    } catch (e) {
      debugPrint('CHAT send failed: $e');
      return 'Could not send. You can only send to friends.';
    }
  }

  Future<String?> sendFile(File f, String name) async {
    if (await f.length() > maxFileBytes) {
      return 'File is too big. Maximum is 3.5 MB.';
    }
    final safe = _safe(name);
    final path = '$myUid/${DateTime.now().millisecondsSinceEpoch}_$safe';
    try {
      await _c.storage.from(bucket).upload(path, f);
    } catch (e) {
      debugPrint('CHAT upload failed: $e');
      return 'Could not upload. Check your internet.';
    }
    try {
      final size = await f.length();
      final row = await _c
          .from('chat_messages')
          .insert({
            'from_uid': myUid,
            'to_uid': peerUid,
            'kind': 'file',
            'file_path': path,
            'file_name': name,
            'file_size': size,
          })
          .select('id, created_at')
          .single();
      final id = row['id'] as String;
      final localName = 'chatfile_${id}_$safe';
      await f.copy('${(await _dir()).path}/$localName');
      await _add(ChatMessage(
        id: id,
        fromUid: myUid,
        toUid: peerUid,
        kind: 'file',
        fileName: name,
        localName: localName,
        fileSize: size,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      ));
      return null;
    } catch (e) {
      debugPrint('CHAT file send failed: $e');
      try {
        await _c.storage.from(bucket).remove([path]);
      } catch (_) {}
      return 'Could not send. You can only send to friends.';
    }
  }

  Future<File?> fileOf(ChatMessage m) async {
    final n = m.localName;
    if (n == null) return null;
    final f = File('${(await _dir()).path}/$n');
    return await f.exists() ? f : null;
  }

  /// Removes the message from this phone only.
  Future<void> deleteLocal(ChatMessage m) async {
    try {
      final f = await fileOf(m);
      if (f != null) await f.delete();
    } catch (_) {}
    messages.value = [for (final x in messages.value) if (x.id != m.id) x];
    await _save();
  }

  void dispose() {
    _disposed = true;
    _ch?.unsubscribe();
    messages.dispose();
  }
}