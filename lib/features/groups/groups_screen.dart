import 'package:flutter/material.dart';
import '../contacts/contact_controller.dart';
import 'group_controller.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'group_detail_screen.dart';
import 'group_call_screen.dart';
import 'group_chat_screen.dart';
import 'group_status.dart';
import '../../utils/net_status.dart';

const _emojis = [
  '🎉', '🔥', '🎮', '🎵', '🍕', '⚽',
  '💼', '📊', '🚀', '💡', '☕', '🌟',
];

const _palette = <int>[
  0xFF0D9488, 0xFF2563EB, 0xFF7C3AED, 0xFFDB2777,
  0xFFEA580C, 0xFF16A34A, 0xFF475569, 0xFFCA8A04,
];

/// Round emoji avatar in the group's colour.
class GroupAvatar extends StatelessWidget {
  final GroupModel g;
  final double size;
  const GroupAvatar({super.key, required this.g, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final c = Color(g.color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.withOpacity(0.7), c],
        ),
      ),
      child: Text(g.emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// Lets the user tick friends (not in [exclude]). Returns their UIDs.
Future<List<String>?> pickFriends(
  BuildContext context,
  ContactController cc, {
  Set<String> exclude = const {},
}) {
  final options = cc.contacts.value
      .where((c) => cc.friends.value.contains(c.uid) && !exclude.contains(c.uid))
      .toList();
  final chosen = <String>{};
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Choose friends'),
        content: SizedBox(
          width: double.maxFinite,
          child: options.isEmpty
              ? const Text('No friends to add.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in options)
                      CheckboxListTile(
                        value: chosen.contains(c.uid),
                        title: Text(c.displayName),
                        onChanged: (v) => setS(() {
                          if (v == true) {
                            chosen.add(c.uid);
                          } else {
                            chosen.remove(c.uid);
                          }
                        }),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, chosen.toList()),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );
}

class GroupsScreen extends StatefulWidget {
  final ContactController contactController;
  final String myUid;
  const GroupsScreen({
    super.key,
    required this.contactController,
    required this.myUid,
  });

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final GroupController _gc = GroupController(widget.myUid);
  final Map<String, bool> _live = {};
  Timer? _poll;

  Future<void> _loadLive() async {
    if (!NetStatus.online.value) return;
    GroupStatus.refresh(widget.myUid);
    try {
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 45))
          .toIso8601String();
      final rows = await Supabase.instance.client
          .from('live_group_calls')
          .select('group_id, video')
          .gte('updated_at', since);
      if (!mounted) return;
      setState(() {
        _live.clear();
        for (final r in rows as List) {
          _live[r['group_id'].toString()] = r['video'] == true;
        }
      });
    } catch (_) {}
  }

  void _openChat(GroupModel g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          groupController: _gc,
          groupId: g.id,
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
  }

  void _joinLive(GroupModel g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupCallScreen(
          groupId: g.id,
          groupName: g.name,
          video: _live[g.id] ?? false,
          emoji: g.emoji,
          color: g.color,
          mode: g.mode,
          groupController: _gc,
          contactController: widget.contactController,
          myUid: widget.myUid,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _gc.start();
    _loadLive();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _loadLive());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = TextEditingController();
    var emoji = _emojis[0];
    var color = _palette[0];
    var mode = 'friends';

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GroupAvatar(
                    g: GroupModel(
                      id: '',
                      name: '',
                      isOwner: true,
                      members: const [],
                      emoji: emoji,
                      color: color,
                      mode: mode,
                    ),
                    size: 72,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    hintText: 'Group name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'friends',
                      label: Text('Friends'),
                      icon: Icon(Icons.celebration_outlined),
                    ),
                    ButtonSegment(
                      value: 'work',
                      label: Text('Work'),
                      icon: Icon(Icons.business_center_outlined),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setS(() => mode = s.first),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in _emojis)
                      GestureDetector(
                        onTap: () => setS(() => emoji = e),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: e == emoji
                                ? Color(color).withOpacity(0.25)
                                : Colors.transparent,
                            border: Border.all(
                              color: e == emoji
                                  ? Color(color)
                                  : Colors.black12,
                            ),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _palette)
                      GestureDetector(
                        onTap: () => setS(() => color = c),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c == color ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: c == color
                                ? [BoxShadow(color: Color(c), blurRadius: 8)]
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Next: choose people'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final uids = await pickFriends(context, widget.contactController);
    if (uids == null || !mounted) return;
    String? err;
    try {
      err = await _gc.create(
      name.text,
      uids,
      emoji: emoji,
      color: color,
      mode: mode,
    );
    } catch (_) {
      err = 'Could not create the group. Check your internet.';
    }
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        child: const Icon(Icons.group_add),
      ),
      body: ValueListenableBuilder<List<GroupModel>>(
        valueListenable: _gc.groups,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return const Center(
                child: Text('No groups yet. Tap + to create one.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final g = list[i];
              final live = _live.containsKey(g.id);
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: live
                        ? Colors.red
                        : Color(g.color).withOpacity(0.35),
                    width: live ? 2 : 1,
                  ),
                ),
                tileColor: Color(g.color).withOpacity(0.12),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GroupAvatar(g: g),
                    if (_live.containsKey(g.id))
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  g.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17),
                ),
                subtitle: Text(
                  '${g.mode == 'work' ? 'Work' : 'Friends'} · ${g.members.length} members',
                ),
                trailing: _live.containsKey(g.id)
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => _joinLive(g),
                        child: const Text('Join live'),
                      )
                    : IconButton(
                        tooltip: 'Group chat',
                        icon: ValueListenableBuilder<Map<String, int>>(
                          valueListenable: GroupStatus.unread,
                          builder: (_, u, __) => Badge(
                            isLabelVisible: (u[g.id] ?? 0) > 0,
                            label: Text('${u[g.id] ?? 0}'),
                            child: const Icon(Icons.chat_bubble_outline),
                          ),
                        ),
                        onPressed: () => _openChat(g),
                      ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupDetailScreen(
                      groupController: _gc,
                      groupId: g.id,
                      contactController: widget.contactController,
                      myUid: widget.myUid,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}