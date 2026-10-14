import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a video file inside the app.
class VideoViewerScreen extends StatefulWidget {
  final File file;
  final String title;

  const VideoViewerScreen({super.key, required this.file, required this.title});

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(widget.file);
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _failed
            ? const Text('Cannot play this video.',
                style: TextStyle(color: Colors.white))
            : !_c.value.isInitialized
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _c.value.aspectRatio,
                        child: VideoPlayer(_c),
                      ),
                      const SizedBox(height: 8),
                      VideoProgressIndicator(_c, allowScrubbing: true),
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _c,
                        builder: (_, v, __) => IconButton(
                          iconSize: 48,
                          color: Colors.white,
                          icon: Icon(
                            v.isPlaying ? Icons.pause_circle : Icons.play_circle,
                          ),
                          onPressed: () =>
                              v.isPlaying ? _c.pause() : _c.play(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}