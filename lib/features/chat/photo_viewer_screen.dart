import 'dart:io';
import 'package:flutter/material.dart';

/// Full screen photo with pinch to zoom.
class PhotoViewerScreen extends StatelessWidget {
  final File file;
  final String title;

  const PhotoViewerScreen({super.key, required this.file, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Cannot show this photo.',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}