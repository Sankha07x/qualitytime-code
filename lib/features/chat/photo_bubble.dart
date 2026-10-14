import 'dart:io';
import 'package:flutter/material.dart';
import 'chat_service.dart';
import 'photo_viewer_screen.dart';

bool isImageName(String? name) {
  final n = (name ?? '').toLowerCase();
  return n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.gif') ||
      n.endsWith('.webp') ||
      n.endsWith('.bmp');
}

/// Small picture inside a chat bubble. Tap opens it full screen.
class PhotoBubble extends StatefulWidget {
  final ChatMessage m;
  final ChatService svc;

  const PhotoBubble({super.key, required this.m, required this.svc});

  @override
  State<PhotoBubble> createState() => _PhotoBubbleState();
}

class _PhotoBubbleState extends State<PhotoBubble> {
  late final Future<File?> _file = widget.svc.fileOf(widget.m);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) {
          return const SizedBox(
            width: 220,
            height: 120,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PhotoViewerScreen(
                file: f,
                title: widget.m.fileName ?? 'Photo',
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              f,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              cacheWidth: 600,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 220,
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        );
      },
    );
  }
}