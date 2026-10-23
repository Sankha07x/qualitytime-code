import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rings group members: in-app signal (phones with the app open) plus a
/// push through the send-call-push function (phones with the app closed).
class GroupRinger {
  GroupRinger._();

  static Future<void> ring({
    required String groupId,
    required String groupName,
    required String emoji,
    required int color,
    required String mode,
    required List<String> members,
    required bool video,
    required String fromUid,
    List<String>? only,
  }) async {
    final targets = (only ?? members).where((u) => u != fromUid).toList();
    if (targets.isEmpty) return;
    final data = <String, dynamic>{
      'from': fromUid,
      'group': groupId,
      'name': groupName,
      'emoji': emoji,
      'color': color,
      'mode': mode,
      'video': video,
    };
    for (final u in targets) {
      unawaited(_send(u, data));
    }
    if (!groupId.startsWith('call_')) {
      unawaited(_push(groupId, video, only));
      Future.delayed(const Duration(seconds: 30),
          () => unawaited(_notifyLive(groupId, video, only)));
    }
  }

  static Future<void> _send(String toUid, Map<String, dynamic> data) async {
    final client = Supabase.instance.client;
    final ch = client.channel('user:$toUid');
    try {
      final ready = Completer<void>();
      ch.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed &&
            !ready.isCompleted) {
          ready.complete();
        }
      });
      await ready.future.timeout(const Duration(seconds: 10));
      await ch.sendBroadcastMessage(event: 'gring', payload: {'d': data});
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('GROUP RING send failed: $e');
    } finally {
      await client.removeChannel(ch);
    }
  }

  /// If the call is still going 30 s later, leave a "tap to join"
  /// notification for people who did not answer.
  static Future<void> _notifyLive(
      String groupId, bool video, List<String>? only) async {
    try {
      final c = Supabase.instance.client;
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
      final live = await c
          .from('live_group_calls')
          .select('group_id')
          .eq('group_id', groupId)
          .gte('updated_at', since)
          .maybeSingle();
      if (live == null) return;
      await c.functions.invoke('send-notify-push', body: {
        'kind': 'group_call',
        'group_id': groupId,
        'video': video,
        if (only != null) 'only': only,
      });
    } catch (e) {
      debugPrint('GROUP LIVE notify failed: $e');
    }
  }

  static Future<void> _push(
      String groupId, bool video, List<String>? only) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-call-push',
        body: {
          'group_id': groupId,
          'call_type': video ? 'video' : 'voice',
          if (only != null) 'callee_uids': only,
        },
      );
    } catch (e) {
      debugPrint('GROUP PUSH failed: $e');
    }
  }
}