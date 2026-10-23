import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/net_status.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/user_avatar.dart';
import '../chat/bubble_shell.dart';
import '../chat/reply_widgets.dart';
import '../contacts/contact_controller.dart';
import 'group_chat_service.dart';
import 'group_controller.dart';
import 'group_status.dart';
import 'groups_screen.dart';

const _nameColors = <int>[
  0xFF0D9488, 0xFF2563EB, 0xFF7C3AED, 0xFFDB2777,
  0xFFEA580C, 0xFF16A34A, 0xFFCA8A04, 0xFF0891B2,
];

class _DayChip extends StatelessWidget {
  final String text;
  const _DayChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  final GroupController groupController;
  final String groupId;
  final ContactController contactController;
  final String myUid;

  const GroupChatScreen({
    super.key,
    required this.groupController,
    required this.groupId,
    required this.contactController,
    required this.myUid,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final GroupChatService _svc =
      GroupChatService(groupId: widget.groupId, myUid: widget.myUid);
  final _ctrl = TextEditingController();
  final _hasText = ValueNotifier<bool>(false);
  bool _popped = false;
  GroupMessage? _replying;
  GroupMessage? _editing;

  @override
  void initState() {
    super.initState();
    _svc.start();
    GroupStatus.markRead(widget.groupId);
    _svc.messages.addListener(_seen);
    _ctrl.addListener(() {
      final h = _ctrl.text.trim().isNotEmpty;
      if (h != _hasText.value) _hasText.value = h;
    });
    NetStatus.online.addListener(_onNet);
  }

  @override
  void dispose() {
    _svc.messages.removeListener(_seen);
    GroupStatus.markRead(widget.groupId);
    NetStatus.online.removeListener(_onNet);
    _ctrl.dispose();
    _hasText.dispose();
    _svc.dispose();
    super.dispose();
  }

  void _seen() => GroupStatus.markRead(widget.groupId);

  void _startReply(GroupMessage m) {
    setState(() {
      _replying = m;
      _editing = null;
    });
  }

  Widget _banner() {
    final e = _editing;
    final m = e ?? _replying;
    if (m == null) return const SizedBox.shrink();
    final who = m.fromUid == widget.myUid
        ? 'You'
        : widget.groupController.nameOf(m.fromUid);
    return ReplyBanner(
      title: e != null ? 'Editing message' : 'Replying to $who',
      text: m.body,
      editing: e != null,
      onClose: () {
        setState(() {
          _replying = null;
          _editing = null;
        });
        if (e != null) _ctrl.clear();
      },
    );
  }

  void _onNet() {
    if (NetStatus.online.value) _svc.load();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _send() async {
    final t = _ctrl.text;
    if (t.trim().isEmpty) return;
    _ctrl.clear();
    HapticFeedback.lightImpact();
    final e = _editing;
    final r = _replying;
    final err = e != null
        ? await _svc.editText(e, t)
        : await _svc.send(t, replyTo: r);
    if (mounted) {
      if (e == null) {
        setState(() => _replying = null);
      } else if (err == null) {
        setState(() => _editing = null);
      } else {
        _ctrl.text = t;
      }
    }
    if (err != null) _snack(err);
  }

  Future<void> _retry(GroupMessage m) async {
    final err = await _svc.send(m.body, retryId: m.id);
    if (err != null) _snack(err);
  }

  Future<void> _menu(GroupMessage m) async {
    HapticFeedback.selectionClick();
    final mine = m.fromUid == widget.myUid;
    final c = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (_svc.canEdit(m))
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                subtitle: const Text('Available for 15 minutes'),
                onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete for everyone'),
                onTap: () => Navigator.pop(ctx, 'del'),
              ),
          ],
        ),
      ),
    );
    if (c == 'reply') {
      _startReply(m);
    } else if (c == 'edit') {
      setState(() {
        _editing = m;
        _replying = null;
      });
      _ctrl.text = m.body;
      _ctrl.selection = TextSelection.collapsed(offset: m.body.length);
    } else if (c == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      _snack('Copied');
    } else if (c == 'del') {
      final err = await _svc.delete(m);
      if (err != null) _snack(err);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _day(DateTime t) {
    final now = DateTime.now();
    if (_sameDay(t, now)) return 'Today';
    if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return '${t.day.toString().padLeft(2, '0')}/'
        '${t.month.toString().padLeft(2, '0')}/${t.year}';
  }

  Color _nameColor(String uid) =>
      Color(_nameColors[uid.hashCode.abs() % _nameColors.length]);

  Widget _status(GroupMessage m) {
    if (m.state == 1) {
      return const Icon(Icons.schedule, size: 13, color: Colors.white70);
    }
    if (m.state == 2) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 14, color: Colors.amberAccent),
          SizedBox(width: 3),
          Text('Failed. Tap to retry',
              style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      );
    }
    return const Icon(Icons.done, size: 14, color: Colors.white70);
  }

  Widget _bubble(GroupMessage m, bool first, bool last) {
    final mine = m.fromUid == widget.myUid;
    final fg = bubbleFg(context, mine);
    final name = widget.groupController.nameOf(m.fromUid);
    final photos = widget.contactController.photos.value;
    if (!mine && !photos.containsKey(m.fromUid)) {
      widget.contactController.fetchPhoto(m.fromUid);
    }
    final content = GestureDetector(
      onTap: m.state == 2 ? () => _retry(m) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine && first)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _nameColor(m.fromUid),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          if (m.replyText != null)
            QuoteBox(
              name: m.replyFrom == widget.myUid
                  ? 'You'
                  : widget.groupController.nameOf(m.replyFrom ?? ''),
              text: m.replyText!,
              fg: fg,
            ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            children: [
              LinkText(m.body, style: TextStyle(color: fg, fontSize: 15)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.editedAt != null && m.state != 2)
                    Text('edited  ',
                        style: TextStyle(
                            color: fg.withOpacity(0.7), fontSize: 11)),
                  if (m.state != 2)
                    Text(hm(m.createdAt),
                        style: TextStyle(
                            color: fg.withOpacity(0.7), fontSize: 11)),
                  if (mine) ...[
                    const SizedBox(width: 5),
                    _status(m),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final shell = BubbleShell(
      mine: mine,
      onLongPress: m.state == 2 ? null : () => _menu(m),
      child: content,
    );
    final pad = EdgeInsets.only(top: first ? 6 : 0);
    if (mine) return Padding(padding: pad, child: shell);
    return Padding(
      padding: pad,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 8),
          last
              ? UserAvatar(name: name, photoUrl: photos[m.fromUid], radius: 15)
              : const SizedBox(width: 30),
          Flexible(child: shell),
        ],
      ),
    );
  }

  Widget _row(List<GroupMessage> items, int idx) {
    final m = items[idx];
    final prev = idx > 0 ? items[idx - 1] : null;
    final next = idx < items.length - 1 ? items[idx + 1] : null;
    final newDay = prev == null || !_sameDay(prev.createdAt, m.createdAt);
    final first = newDay || prev.fromUid != m.fromUid;
    final last = next == null ||
        next.fromUid != m.fromUid ||
        !_sameDay(next.createdAt, m.createdAt);
    final inner = _bubble(m, first, last);
    final b = RepaintBoundary(
      child: m.state == 2
          ? inner
          : SwipeReply(onReply: () => _startReply(m), child: inner),
    );
    if (!newDay) return b;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [_DayChip(_day(m.createdAt)), b],
    );
  }

  Widget _messages() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _svc.messages,
        _svc.loading,
        _svc.loadError,
        widget.contactController.photos,
        widget.groupController.names,
      ]),
      builder: (context, _) {
        if (_svc.loading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = _svc.messages.value;
        if (items.isEmpty) {
          final err = _svc.loadError.value;
          if (err != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(err, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _svc.retryLoad,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No messages yet.\nSay hi to the group!',
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          itemBuilder: (_, i) => _row(items, items.length - 1 - i),
        );
      },
    );
  }

  Widget _input() {
    final s = Theme.of(context).colorScheme;
    final accent = Color(AppSettings.accent.value);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: s.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: s.outlineVariant),
                ),
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(
                        GroupChatService.maxLen),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Message the group',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
              valueListenable: _hasText,
              builder: (_, has, __) => GestureDetector(
                onTap: has ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: has ? accent : Colors.grey.shade400,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupModel>>(
      valueListenable: widget.groupController.groups,
      builder: (context, list, _) {
        final g = list.where((x) => x.id == widget.groupId).firstOrNull;
        if (g == null) {
          if (!_popped) {
            _popped = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _snack('This group is not available anymore.');
              Navigator.of(context).maybePop();
            });
          }
          return const Scaffold();
        }
        final member = g.isOwner || g.members.contains(widget.myUid);
        final s = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                GroupAvatar(g: g, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('${g.members.length} members',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(g.color).withOpacity(0.22), s.surface],
              ),
            ),
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: NetStatus.online,
                  builder: (context, on, _) => on
                      ? const SizedBox.shrink()
                      : Container(
                          width: double.infinity,
                          color: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: const Text(
                            "You're offline. Messages will not send.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white, fontSize: 12.5),
                          ),
                        ),
                ),
                Expanded(child: _messages()),
                if (member)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [_banner(), _input()],
                  )
                else
                  SafeArea(
                    top: false,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: s.surfaceVariant,
                      child: const Text(
                        'You are no longer a member of this group.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}