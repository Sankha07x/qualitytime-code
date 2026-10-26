import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VoiceMessage {
  final String id;
  final String fromUid;
  final String toUid;
  final String? path;
  final int seconds;
  final DateTime createdAt;
  final DateTime? playedAt;
  final bool viewOnce;
  const VoiceMessage({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.path,
    required this.seconds,
    required this.createdAt,
    required this.playedAt,
    this.viewOnce = false,
  });

  factory VoiceMessage.fromRow(Map<String, dynamic> r) => VoiceMessage(
        viewOnce: r['view_once'] == true,
        id: r['id'] as String,
        fromUid: r['from_uid'] as String,
        toUid: r['to_uid'] as String,
        path: r['path'] as String?,
        seconds: (r['seconds'] as num).toInt(),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        playedAt: r['played_at'] == null
            ? null
            : DateTime.parse(r['played_at'] as String).toLocal(),
      );
}

/// Voice messages with one contact. Audio goes to the private Supabase
/// bucket "voice"; once the receiver plays it, the cloud copy is deleted
/// and both phones keep their own copy.
class VoiceService {
  static const maxSeconds = 120;

  final String myUid;
  final String peerUid;
  final SupabaseClient _c = Supabase.instance.client;
  final messages = ValueNotifier<List<VoiceMessage>>([]);
  final AudioRecorder _rec = AudioRecorder();
  RealtimeChannel? _ch;
  bool _disposed = false;
  DateTime? _recStart;

  VoiceService({required this.myUid, required this.peerUid});

  Future<void> start() async {
    await refresh();
    if (_disposed) return;
    _ch = _c
        .channel('voice:$myUid:$peerUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'voice_messages',
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final rows = await _c
          .from('voice_messages')
          .select()
          .or('and(from_uid.eq.$myUid,to_uid.eq.$peerUid),'
              'and(from_uid.eq.$peerUid,to_uid.eq.$myUid)')
          .order('created_at', ascending: false)
          .limit(80);
      final list = [
        for (final r in rows as List)
          VoiceMessage.fromRow(Map<String, dynamic>.from(r)),
      ].reversed.toList();
      if (!_disposed) messages.value = list;
    } catch (e) {
      debugPrint('VOICE refresh failed: $e');
    }
  }

  Future<File> _local(String id) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/voice_$id.m4a');
  }

  void _tryDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // ---------- recording ----------

  Future<bool> startRecording() async {
    try {
      if (!await _rec.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/vm_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _recStart = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('VOICE start failed: $e');
      return false;
    }
  }

  Stream<Amplitude> amplitude(Duration every) => _rec.onAmplitudeChanged(every);

  /// Stops recording. Null if it was too short.
  Future<({File file, int seconds})?> stopRecording() async {
    final start = _recStart;
    _recStart = null;
    try {
      final p = await _rec.stop();
      if (p == null || start == null) return null;
      final secs = DateTime.now().difference(start).inSeconds;
      if (secs < 1) {
        _tryDelete(p);
        return null;
      }
      return (file: File(p), seconds: secs.clamp(1, maxSeconds));
    } catch (e) {
      debugPrint('VOICE stop failed: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    _recStart = null;
    try {
      final p = await _rec.stop();
      if (p != null) _tryDelete(p);
    } catch (_) {}
  }

  // ---------- send ----------

  /// Returns an error text, or null on success.
  Future<String?> send(File f, int seconds, {bool viewOnce = false}) async {
    final path = '$myUid/${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _c.storage.from('voice').upload(
            path,
            f,
            fileOptions: const FileOptions(contentType: 'audio/mp4'),
          );
    } catch (e) {
      debugPrint('VOICE upload failed: $e');
      return 'Could not upload. Check your internet.';
    }
    try {
      final row = await _c
          .from('voice_messages')
          .insert({
            'from_uid': myUid,
            'to_uid': peerUid,
            'path': path,
            'seconds': seconds,
            if (viewOnce) 'view_once': true,
          })
          .select('id')
          .single();
      final id = row['id'] as String;
      if (!viewOnce) await f.copy((await _local(id)).path); // my own copy for replay
      _tryDelete(f.path);
      unawaited(_push(seconds));
      await refresh();
      return null;
    } catch (e) {
      debugPrint('VOICE insert failed: $e');
      try {
        await _c.storage.from('voice').remove([path]);
      } catch (_) {}
      return 'Could not send. You can only send to friends.';
    }
  }

  Future<void> _push(int seconds) async {
    try {
      await _c.functions.invoke(
        'send-voice-push',
        body: {'to_uid': peerUid, 'seconds': seconds},
      );
    } catch (e) {
      debugPrint('VOICE push failed: $e');
    }
  }

  // ---------- play ----------

  /// The audio file on this phone. The first time the receiver plays a
  /// message it is downloaded, then the cloud copy is deleted.
  Future<File?> fileFor(VoiceMessage m) async {
    final local = await _local(m.id);
    if (await local.exists()) return local;
    final p = m.path;
    if (p == null || m.toUid != myUid) return null;
    try {
      final bytes = await _c.storage.from('voice').download(p);
      await local.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('VOICE download failed: $e');
      return null;
    }
    unawaited(_clearCloud(m));
    return local;
  }

  Future<void> _clearCloud(VoiceMessage m) async {
    var removed = false;
    try {
      await _c.storage.from('voice').remove([m.path!]);
      removed = true;
    } catch (e) {
      debugPrint('VOICE cloud delete failed: $e');
    }
    try {
      await _c.from('voice_messages').update({
        'played_at': DateTime.now().toUtc().toIso8601String(),
        if (removed) 'path': null,
      }).eq('id', m.id);
    } catch (e) {
      debugPrint('VOICE mark played failed: $e');
    }
  }

  /// View-once message was played: remove the audio from this phone.
  Future<void> consume(VoiceMessage m) async {
    try {
      final l = await _local(m.id);
      if (await l.exists()) await l.delete();
    } catch (_) {}
  }

  Future<void> delete(VoiceMessage m) async {
    try {
      if (m.path != null) await _c.storage.from('voice').remove([m.path!]);
    } catch (_) {}
    try {
      await _c.from('voice_messages').delete().eq('id', m.id);
    } catch (_) {}
    try {
      final l = await _local(m.id);
      if (await l.exists()) await l.delete();
    } catch (_) {}
    await refresh();
  }

  void dispose() {
    _disposed = true;
    _ch?.unsubscribe();
    _rec.dispose();
    messages.dispose();
  }
}