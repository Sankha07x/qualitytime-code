import 'package:flutter/material.dart';

/// Shows a photo full screen. Pinch to zoom, tap to close.
void showPhotoViewer(BuildContext context, String url, {String? title}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(url: url, title: title),
    ),
  );
}

class _PhotoViewer extends StatelessWidget {
  final String url;
  final String? title;

  const _PhotoViewer({required this.url, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title ?? ''),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (c, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (c, e, s) => const Icon(
                Icons.broken_image,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}