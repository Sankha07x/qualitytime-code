import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Blurred photo backdrop. The blur is done once on a tiny copy of the
/// photo and then stretched, so it costs almost nothing per frame.
class BlurredPhoto extends StatefulWidget {
  final String url;
  const BlurredPhoto({super.key, required this.url});

  @override
  State<BlurredPhoto> createState() => _BlurredPhotoState();
}

class _BlurredPhotoState extends State<BlurredPhoto> {
  ui.Image? _img;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BlurredPhoto old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _unlisten();
      _load();
    }
  }

    void _load() {
    final provider =
        ResizeImage(CachedNetworkImageProvider(widget.url), width: 96);
    final stream = provider.resolve(const ImageConfiguration());
    final l = ImageStreamListener(
      (info, _) => _blur(info.image),
      onError: (_, __) {},
    );
    _stream = stream;
    _listener = l;
    stream.addListener(l);
  }

  void _unlisten() {
    final s = _stream, l = _listener;
    if (s != null && l != null) s.removeListener(l);
  }

  Future<void> _blur(ui.Image src) async {
    final w = src.width, h = src.height;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 4,
          sigmaY: 4,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImage(src, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    final out = await rec.endRecording().toImage(w, h);
    if (!mounted) {
      out.dispose();
      return;
    }
    final old = _img;
    setState(() => _img = out);
    old?.dispose();
  }

  @override
  void dispose() {
    _unlisten();
    _img?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _img == null ? 0 : 1,
      duration: const Duration(milliseconds: 300),
      child: SizedBox.expand(
        child: RawImage(
          image: _img,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}