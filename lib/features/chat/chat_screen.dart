import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';
import '../../utils/user_avatar.dart';
import '../voice/voice_service.dart';
import 'bubble_shell.dart';
import 'chat_input_bar.dart';
import 'chat_service.dart';
import 'file_opener.dart';
import 'photo_bubble.dart';
import 'photo_bubble.dart';
import 'voice_bubble.dart';

class _Item {
  final DateTime at;
  final ChatMessage? chat;
  final VoiceMessage? voice;
  _Item(this.at, {this.chat, this.voice});
}

/// One chat window: text, files and voice messages in a single timeline.
class ChatScreen extends StatefulWidget {
  final String contactName;
  final String contactUid;
  final String myUid;
  final String? photoUrl;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.contactUid,
    required this.myUid,
    this.photoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chat =
      ChatService(myUid: widget.myUid, peerUid: widget.contactUid);
  late final VoiceService _voice =
      VoiceService(myUid: widget.myUid, peerUid: widget.contactUid);
  final _player = VoicePlayerController();

  @override
  void initState() {
    super.initState();
    _chat.start();
    _voice.start();
  }

  @override
  void dispose() {
    _player.dispose();
    _chat.dispose();
    // small delay so a recording in progress can be cancelled first
    Future.delayed(const Duration(milliseconds: 500), _voice.dispose);
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _attach() async {
    final x = await openFile();
    if (x == null) return;
    final err = await _chat.sendFile(File(x.path), x.name);
    if (err != null) _snack(err);
  }

  Future<bool> _ask(String title, String body) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      )) ==
      true;

  Future<void> _delChat(ChatMessage m) async {
    final mine = m.fromUid == widget.myUid;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'me'),
            child: const Text('Delete for me'),
          ),
          if (mine)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice == 'me') {
      await _chat.deleteLocal(m);
    } else if (choice == 'all') {
      final err = await _chat.deleteForEveryone(m);
      if (err != null) _snack(err);
    }
  }

  Future<void> _delVoice(VoiceMessage m) async {
    if (!await _ask('Delete voice message?', 'It is removed for both of you.')) {
      return;
    }
    if (_player.playingId == m.id) await _player.stop();
    await _voice.delete(m);
  }

  List<_Item> _items() => [
        for (final m in _chat.messages.value) _Item(m.createdAt, chat: m),
        for (final v in _voice.messages.value) _Item(v.createdAt, voice: v),
      ]..sort((a, b) => a.at.compareTo(b.at));

  Widget _bubble(_Item it) {
    final v = it.voice;
    if (v != null) {
      return VoiceBubble(
        m: v,
        mine: v.fromUid == widget.myUid,
        player: _player,
        svc: _voice,
        onError: _snack,
        onLongPress: () => _delVoice(v),
      );
    }
    final m = it.chat!;
    final mine = m.fromUid == widget.myUid;
    final fg = bubbleFg(context, mine);
    final content = m.kind == 'file' && isImageName(m.fileName)
        ? PhotoBubble(m: m, svc: _chat)
        : m.kind == 'file' && isImageName(m.fileName)
        ? PhotoBubble(m: m, svc: _chat)
        : m.kind == 'file'
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 22, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${m.fileName ?? 'File'}\n${((m.fileSize ?? 0) / 1024).round()} KB',
                  style: TextStyle(color: fg),
                ),
              ),
            ],
          )
        : Text(m.body ?? '', style: TextStyle(color: fg, fontSize: 15));
    return BubbleShell(
      mine: mine,
      onLongPress: () => _delChat(m),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: m.kind == 'file' && !isImageName(m.fileName)
                ? () => openChatFile(context, _chat, m)
                : null,
            child: Align(alignment: Alignment.centerLeft, child: content),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hm(m.createdAt),
                  style:
                      TextStyle(color: fg.withOpacity(0.7), fontSize: 11)),
              if (mine) ...[
                const SizedBox(width: 6),
                Icon(m.status > 0 ? Icons.done_all : Icons.done,
                    size: 14,
                    color: Colors.white
                        .withOpacity(m.status == 2 ? 1 : 0.85)),
                const SizedBox(width: 2),
                Text(
                    m.status == 2
                        ? 'Read'
                        : (m.status == 1 ? 'Delivered' : 'Sent'),
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _background() {
    final wp = AppSettings.wallpaper.value;
    final s = Theme.of(context).colorScheme;
    if (wp != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(wp), fit: BoxFit.cover),
          ColoredBox(color: s.surface.withOpacity(0.55)),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.primaryContainer.withOpacity(0.6), s.surface],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              name: widget.contactName,
              photoUrl: widget.photoUrl,
              radius: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.contactName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _background(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation:
                        Listenable.merge([_chat.messages, _voice.messages]),
                    builder: (context, _) {
                      final items = _items();
                      if (items.isEmpty) {
                        return const Center(
                          child: Text('No messages yet. Say hi!'),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: items.length,
                        itemBuilder: (_, i) =>
                            _bubble(items[items.length - 1 - i]),
                      );
                    },
                  ),
                ),
                ChatInputBar(
                  voice: _voice,
                  onSendText: _chat.sendText,
                  onAttach: _attach,
                  onRecordStart: _player.stop,
                  onMessage: _snack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}