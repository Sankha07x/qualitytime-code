import 'package:flutter/material.dart';
import '../../utils/user_avatar.dart';
import 'contact_controller.dart';

/// The bell page. It only lists what is new. Tapping a request or chat
/// opens the right screen. Missed calls are shown for information.
class NotificationsScreen extends StatelessWidget {
  final ContactController contactController;
  final ValueNotifier<Map<String, int>> unread;
  final ValueNotifier<Map<String, String>> preview;
  final ValueNotifier<List<Map<String, dynamic>>> missed;
  final String Function(String uid) nameFor;
  final void Function(String uid) onOpenChat;
  final VoidCallback onOpenAdd;

  const NotificationsScreen({
    super.key,
    required this.contactController,
    required this.unread,
    required this.preview,
    required this.missed,
    required this.nameFor,
    required this.onOpenChat,
    required this.onOpenAdd,
  });

  String? _photo(String uid) {
    final p = contactController.photos.value[uid];
    return (p == null || p.isEmpty) ? null : p;
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final cc = contactController;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AnimatedBuilder(
        animation:
            Listenable.merge([cc.incoming, unread, preview, cc.photos, missed]),
        builder: (context, _) {
          final requests = cc.incoming.value;
          final chats = unread.value.entries.toList();
          final calls = missed.value;
          if (requests.isEmpty && chats.isEmpty && calls.isEmpty) {
            return const Center(child: Text('Nothing new.'));
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final r in requests)
                ListTile(
                  leading: UserAvatar(
                    name: r['name'] ?? '?',
                    photoUrl: _photo(r['uid'] ?? ''),
                  ),
                  title: Text(r['name'] ?? ''),
                  subtitle: const Text('Sent you a friend request'),
                  trailing: const Icon(Icons.person_add_alt_1),
                  onTap: onOpenAdd,
                ),
              for (final m in calls)
                ListTile(
                  leading: UserAvatar(
                    name: nameFor('${m['from_uid']}'),
                    photoUrl: _photo('${m['from_uid']}'),
                  ),
                  title: Text(
                    nameFor('${m['from_uid']}'),
                    style: TextStyle(
                      fontWeight: m['seen'] == true
                          ? FontWeight.normal
                          : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Missed ${m['video'] == true ? 'video' : 'voice'} call'
                    ' \u00b7 ${_ago(m['created_at']?.toString())}',
                  ),
                  trailing: Icon(
                    m['video'] == true
                        ? Icons.videocam_off
                        : Icons.phone_missed,
                    color: Colors.redAccent,
                  ),
                ),
              for (final e in chats)
                ListTile(
                  leading: UserAvatar(
                    name: nameFor(e.key),
                    photoUrl: _photo(e.key),
                  ),
                  title: Text(nameFor(e.key)),
                  subtitle: Text(
                    (preview.value[e.key] ?? '').isEmpty
                        ? 'New message'
                        : preview.value[e.key]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Badge(label: Text('${e.value}')),
                  onTap: () => onOpenChat(e.key),
                ),
            ],
          );
        },
      ),
    );
  }
}