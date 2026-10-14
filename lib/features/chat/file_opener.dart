import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'chat_service.dart';
import 'pdf_viewer_screen.dart';
import 'video_viewer_screen.dart';

bool isVideoName(String? name) {
  final n = (name ?? '').toLowerCase();
  return n.endsWith('.mp4') ||
      n.endsWith('.mkv') ||
      n.endsWith('.mov') ||
      n.endsWith('.webm') ||
      n.endsWith('.3gp') ||
      n.endsWith('.avi');
}

/// Opens a received or sent file: video and PDF inside the app,
/// everything else with the phone's own app.
Future<void> openChatFile(
    BuildContext context, ChatService svc, ChatMessage m) async {
  final f = await svc.fileOf(m);
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (f == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('File not found on this phone.')),
    );
    return;
  }
  final name = m.fileName ?? 'File';
  if (isVideoName(name)) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoViewerScreen(file: f, title: name),
      ),
    );
  } else if (name.toLowerCase().endsWith('.pdf')) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(file: f, title: name),
      ),
    );
  } else {
    final r = await OpenFilex.open(f.path);
    if (r.type != ResultType.done) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app on this phone can open this file.')),
      );
    }
  }
}
