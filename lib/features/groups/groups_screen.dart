import 'package:flutter/material.dart';
import '../contacts/contact_controller.dart';
import 'group_controller.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_colors.dart';
import '../../utils/user_avatar.dart';
import '../contacts/contact_model.dart';
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

/// Reusable Add-People bottom sheet with rounded corners, drag handle,
/// search box, local frequent-contacts row, and "Ring again" support.
Future<List<String>?> pickFriends(
  BuildContext context,
  ContactController cc, {
  Set<String> exclude = const {},
  Map<String, GroupRingStatus>? rungStatus,
  void Function(String uid)? onRingAgain,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddPeopleSheet(
      cc: cc,
      exclude: exclude,
      rungStatus: rungStatus,
      onRingAgain: onRingAgain,
    ),
  );
}

class _AddPeopleSheet extends StatefulWidget {
  final ContactController cc;
  final Set<String> exclude;
  final Map<String, GroupRingStatus>? rungStatus;
  final void Function(String uid)? onRingAgain;

  const _AddPeopleSheet({
    required this.cc,
    required this.exclude,
    this.rungStatus,
    this.onRingAgain,
  });

  @override
  State<_AddPeopleSheet> createState() => _AddPeopleSheetState();
}

class _AddPeopleSheetState extends State<_AddPeopleSheet> {
  final Set<String> _chosen = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  List<ContactModel> _frequent = [];
  Map<String, GroupRingStatus> _localRungStatus = {};

  @override
  void initState() {
    super.initState();
    if (widget.rungStatus != null) {
      _localRungStatus = Map.of(widget.rungStatus!);
    }
    _calcFrequent();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _calcFrequent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLog = prefs.getString('call_log_v1');
      final counts = <String, int>{};
      if (rawLog != null && rawLog.isNotEmpty) {
        final list = jsonDecode(rawLog);
        if (list is List) {
          for (final e in list) {
            if (e is Map && e['uid'] is String) {
              final uid = e['uid'] as String;
              counts[uid] = (counts[uid] ?? 0) + 2;
            }
          }
        }
      }
      final dir = await getApplicationDocumentsDirectory();
      final allFiles = dir.listSync();
      for (final f in allFiles) {
        if (f is File && f.path.contains('chat_') && f.path.endsWith('.json')) {
          final name = f.uri.pathSegments.last;
          final uid = name.replaceFirst('chat_', '').replaceFirst('.json', '');
          counts[uid] = (counts[uid] ?? 0) + 1;
        }
      }

      final valid = widget.cc.contacts.value
          .where((c) =>
              widget.cc.friends.value.contains(c.uid) &&
              !widget.exclude.contains(c.uid))
          .toList();

      valid.sort((a, b) {
        final ca = counts[a.uid] ?? 0;
        final cb = counts[b.uid] ?? 0;
        if (ca != cb) return cb.compareTo(ca);
        return a.displayName.compareTo(b.displayName);
      });

      if (mounted) {
        setState(() {
          _frequent = valid.take(6).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        final fallback = widget.cc.contacts.value
            .where((c) =>
                widget.cc.friends.value.contains(c.uid) &&
                !widget.exclude.contains(c.uid))
            .take(6)
            .toList();
        setState(() => _frequent = fallback);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.bottomBar(context);
    final border = AppColors.tileBorder(context);
    final options = widget.cc.contacts.value
        .where((c) =>
            widget.cc.friends.value.contains(c.uid) &&
            !widget.exclude.contains(c.uid) &&
            (_query.isEmpty ||
                c.displayName.toLowerCase().contains(_query.toLowerCase())))
        .toList();

    final photos = widget.cc.photos.value;

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: border, width: 1.2)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  widget.rungStatus != null ? 'Add to call' : 'Add friends',
                  style: TextStyle(
                    color: AppColors.textMain(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_chosen.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent(context).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_chosen.length}',
                      style: TextStyle(
                        color: AppColors.accent(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close,
                      color: AppColors.textSecondary(context), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Search Box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border.withOpacity(0.4)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                style:
                    TextStyle(color: AppColors.textMain(context), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search people...',
                  hintStyle: TextStyle(
                      color: AppColors.textSecondary(context).withOpacity(0.7),
                      fontSize: 13.5),
                  prefixIcon: Icon(Icons.search,
                      size: 19, color: AppColors.textSecondary(context)),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          child: Icon(Icons.clear,
                              size: 16,
                              color: AppColors.textSecondary(context)),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),

          // Frequent Row
          if (_query.isEmpty && _frequent.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Frequent',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _frequent.length,
                itemBuilder: (context, i) {
                  final c = _frequent[i];
                  final isSel = _chosen.contains(c.uid);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSel) {
                          _chosen.remove(c.uid);
                        } else {
                          _chosen.add(c.uid);
                        }
                      });
                    },
                    child: Container(
                      width: 62,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              UserAvatar(
                                name: c.displayName,
                                photoUrl: photos[c.uid],
                                radius: 20,
                              ),
                              if (isSel)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 15,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      color: AppColors.accent(context),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: bg, width: 1.5),
                                    ),
                                    child: const Icon(Icons.check,
                                        size: 10, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.displayName.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSel
                                  ? AppColors.textMain(context)
                                  : AppColors.textSecondary(context),
                              fontSize: 11,
                              fontWeight:
                                  isSel ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(color: border.withOpacity(0.4), height: 12),
          ],

          // Contacts List
          Expanded(
            child: options.isEmpty
                ? Center(
                    child: Text(
                      'No friends found.',
                      style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13.5),
                    ),
                  )
                : ListView.builder(
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final c = options[i];
                      final isSel = _chosen.contains(c.uid);
                      final rStatus = _localRungStatus[c.uid];
                      final canRingAgain = widget.onRingAgain != null &&
                          (rStatus == GroupRingStatus.noAnswer ||
                              rStatus == GroupRingStatus.declined);

                      return ListTile(
                        dense: true,
                        leading: UserAvatar(
                          name: c.displayName,
                          photoUrl: photos[c.uid],
                          radius: 18,
                        ),
                        title: Text(
                          c.displayName,
                          style: TextStyle(
                            color: AppColors.textMain(context),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: canRingAgain
                            ? Text(
                                rStatus == GroupRingStatus.declined
                                    ? 'Declined call'
                                    : 'No answer',
                                style: const TextStyle(
                                  color: Color(0xFFEF5350),
                                  fontSize: 12,
                                ),
                              )
                            : null,
                        trailing: canRingAgain
                            ? TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.amber.shade300,
                                  backgroundColor:
                                      Colors.amber.withOpacity(0.12),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text('Ring again',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                onPressed: () {
                                  widget.onRingAgain?.call(c.uid);
                                  setState(() {
                                    _localRungStatus[c.uid] =
                                        GroupRingStatus.calling;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Ringing ${c.displayName} again...'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              )
                            : Checkbox(
                                value: isSel,
                                activeColor: AppColors.accent(context),
                                checkColor: Colors.white,
                                side: BorderSide(
                                    color: AppColors.textSecondary(context)
                                        .withOpacity(0.5)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _chosen.add(c.uid);
                                    } else {
                                      _chosen.remove(c.uid);
                                    }
                                  });
                                },
                              ),
                        onTap: () {
                          if (canRingAgain) return;
                          setState(() {
                            if (isSel) {
                              _chosen.remove(c.uid);
                            } else {
                              _chosen.add(c.uid);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),

          // Confirm button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent(context),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context, _chosen.toList()),
                  child: Text(
                    _chosen.isEmpty ? 'Done' : 'Confirm (${_chosen.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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