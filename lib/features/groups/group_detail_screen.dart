import 'package:flutter/material.dart';
import '../../core/signaling/group_ring_service.dart';
import '../../utils/user_avatar.dart';
import '../contacts/contact_controller.dart';
import 'group_controller.dart';
import 'groups_screen.dart';
import 'group_call_screen.dart';
import 'group_chat_screen.dart';

class GroupDetailScreen extends StatelessWidget {
  final GroupController groupController;
  final String groupId;
  final ContactController contactController;
  final String myUid;

  const GroupDetailScreen({
    super.key,
    required this.groupController,
    required this.groupId,
    required this.contactController,
    required this.myUid,
  });

  Future<void> _add(BuildContext context, GroupModel g) async {
    final uids = await pickFriends(
      context,
      contactController,
      exclude: g.members.toSet(),
    );
    if (uids == null) return;
    final err = await groupController.addMembers(g.id, uids);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _call(BuildContext context, GroupModel g, bool video) {
    GroupRinger.ring(
      groupId: g.id,
      groupName: g.name,
      emoji: g.emoji,
      color: g.color,
      mode: g.mode,
      members: g.members,
      video: video,
      fromUid: myUid,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          groupId: g.id,
          groupName: g.name,
          video: video,
          emoji: g.emoji,
          color: g.color,
          mode: g.mode,
          groupController: groupController,
          contactController: contactController,
          myUid: myUid,
        ),
      ),
    );
  }

  void _chat(BuildContext context, GroupModel g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupController: groupController,
          groupId: g.id,
          contactController: contactController,
          myUid: myUid,
        ),
      ),
    );
  }

  Widget _header(BuildContext context, GroupModel g) {
    final c = Color(g.color);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [c.withOpacity(0.45), c.withOpacity(0.08)],
        ),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          GroupAvatar(g: g, size: 92),
          const SizedBox(height: 12),
          Text(
            g.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${g.mode == 'work' ? 'Work group' : 'Friends group'}'
            ' · ${g.members.length} members',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: c),
                  onPressed: () => _call(context, g, false),
                  icon: const Icon(Icons.call),
                  label: const Text('Voice'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: c),
                  onPressed: () => _call(context, g, true),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Video'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _member(BuildContext context, GroupModel g, String u,
      Map<String, String> photos) {
    if (u != myUid && !photos.containsKey(u)) contactController.fetchPhoto(u);
    final name = groupController.nameOf(u);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black12),
        ),
        tileColor: Color(g.color).withOpacity(0.07),
        leading: UserAvatar(name: name, photoUrl: photos[u]),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(u == myUid ? 'You' : u),
        trailing: (g.isOwner && u != myUid)
            ? IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => groupController.removeMember(g.id, u),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupModel>>(
      valueListenable: groupController.groups,
      builder: (context, list, _) {
        final g = list.where((x) => x.id == groupId).firstOrNull;
        if (g == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const Scaffold();
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              if (g.members.contains(myUid))
                IconButton(
                  tooltip: 'Add people',
                  icon: const Icon(Icons.person_add),
                  onPressed: () => _add(context, g),
                ),
            ],
          ),
          body: ValueListenableBuilder<Map<String, String>>(
            valueListenable: contactController.photos,
            builder: (context, photos, _) => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _header(context, g),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: () => _chat(context, g),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Open group chat'),
                ),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 8),
                  child: Text('Members',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                for (final u in g.members) _member(context, g, u, photos),
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => g.isOwner
                      ? groupController.deleteGroup(g.id)
                      : groupController.removeMember(g.id, myUid),
                  child: Text(g.isOwner ? 'Delete group' : 'Leave group'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}