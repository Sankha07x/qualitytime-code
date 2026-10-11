import 'package:flutter/material.dart';
import '../../core/signaling/group_ring_service.dart';
import '../contacts/contact_controller.dart';
import 'group_controller.dart';
import 'groups_screen.dart';
import 'group_call_screen.dart';

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
              IconButton(
                tooltip: 'Group voice call',
                icon: const Icon(Icons.call),
                onPressed: () => _call(context, g, false),
              ),
              IconButton(
                tooltip: 'Group video call',
                icon: const Icon(Icons.videocam),
                onPressed: () => _call(context, g, true),
              ),
              if (g.isOwner)
                IconButton(
                  tooltip: 'Add people',
                  icon: const Icon(Icons.person_add),
                  onPressed: () => _add(context, g),
                ),
            ],
          ),
          body: ListView(
            children: [
              const SizedBox(height: 16),
              Center(child: GroupAvatar(g: g, size: 84)),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  g.mode == 'work' ? 'Work group' : 'Friends group',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              for (final u in g.members)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(groupController.nameOf(u)),
                  subtitle: Text(u),
                  trailing: (g.isOwner && u != myUid)
                      ? IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () =>
                              groupController.removeMember(g.id, u),
                        )
                      : null,
                ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => g.isOwner
                      ? groupController.deleteGroup(g.id)
                      : groupController.removeMember(g.id, myUid),
                  child: Text(g.isOwner ? 'Delete group' : 'Leave group'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}