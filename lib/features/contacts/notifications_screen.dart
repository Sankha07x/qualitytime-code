import 'package:flutter/material.dart';
import '../../utils/user_avatar.dart';
import 'contact_controller.dart';

/// The bell page. It only lists what is new. Tapping an item opens the
/// right screen (Add friend for requests, the chat for messages).
class NotificationsScreen extends StatelessWidget {
  final ContactController contactController;
  final ValueNotifier<Map<String, int>> unread;
  final ValueNotifier<Map<String, String>> preview;
  final String Function(String uid) nameFor;
  final void Function(String uid) onOpenChat;
  final VoidCallback onOpenAdd;

  const NotificationsScreen({
    super.key,
    required this.contactController,
    required this.unread,
    required this.preview,
    required this.nameFor,
    required this.onOpenChat,
    required this.onOpenAdd,
  });

  String? _photo(String uid) {
    final p = contactController.photos.value[uid];
    return (p == null || p.isEmpty) ? null : p;
  }

  @override
  Widget build(BuildContext context) {
    final cc = contactController;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AnimatedBuilder(
        animation: Listenable.merge([cc.incoming, unread, preview, cc.photos]),
        builder: (context, _) {
          final requests = cc.incoming.value;
          final chats = unread.value.entries.toList();
          if (requests.isEmpty && chats.isEmpty) {
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