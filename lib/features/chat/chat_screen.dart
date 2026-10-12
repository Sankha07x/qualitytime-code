import 'package:flutter/material.dart';
import '../../utils/user_avatar.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'chat_service.dart';

/// Chat window with one friend.
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
  late final ChatService _svc;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc = ChatService(myUid: widget.myUid, peerUid: widget.contactUid);
    _svc.start();
  }

  @override
  void dispose() {
    _svc.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _send() async {
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;
    _ctrl.clear();
    final err = await _svc.sendText(text);
    if (err != null && mounted) {
      _ctrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _attach() async {
    final x = await openFile();
    if (x == null) return;
    final err = await _svc.sendFile(File(x.path), x.name);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.fromUid == widget.myUid;
    final cs = Theme.of(context).colorScheme;
    final time = '${_two(m.createdAt.hour)}:${_two(m.createdAt.minute)}';
    final content = m.kind == 'file'
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${m.fileName ?? 'File'}\n${((m.fileSize ?? 0) / 1024).round()} KB',
                ),
              ),
            ],
          )
        : Text(m.body ?? '');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: content),
            const SizedBox(height: 2),
            Text(time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              name: widget.contactName,
              photoUrl: widget.photoUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.contactName, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: _svc.messages,
              builder: (context, list, _) {
                if (list.isEmpty) {
                  return const Center(child: Text('No messages yet. Say hi!'));
                }
                final rev = list.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: rev.length,
                  itemBuilder: (_, i) => _bubble(rev[i]),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  IconButton(                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _attach,
                  ),
                  IconButton(                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}