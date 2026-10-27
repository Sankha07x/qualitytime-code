import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class MediaCompress {
  static const int _minBytes = 153600; // 150 KB

  static bool isCompressibleImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.heic') ||
        n.endsWith('.heif') ||
        n.endsWith('.webp') ||
        n.endsWith('.bmp');
  }

  /// Returns the display name with .jpg extension when compression was used.
  static String jpgName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return '$base.jpg';
  }

  /// Compresses an image file for chat (JPEG quality 80, max 1600 px, no EXIF).
  /// Never blocks sending: on any error or if not smaller, returns [input].
  static Future<File> compressImageForChat(File input, String name) async {
    try {
      if (!isCompressibleImage(name)) return input;
      final before = await input.length();
      if (before <= _minBytes) return input;

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/cmp_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final xfile = await FlutterImageCompress.compressAndGetFile(
        input.absolute.path,
        outPath,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );

      if (xfile == null) return input;
      final outFile = File(xfile.path);
      if (!await outFile.exists()) return input;

      final after = await outFile.length();
      if (after >= before || after == 0) {
        try {
          await outFile.delete();
        } catch (_) {}
        return input;
      }

      debugPrint('COMPRESS: $before -> $after bytes');
      return outFile;
    } catch (e) {
      debugPrint('COMPRESS failed: $e');
      return input;
    }
  }

  /// Compresses raw avatar bytes before profile upload.
  static Future<Uint8List> compressAvatarBytes(Uint8List bytes) async {
    try {
      if (bytes.lengthInBytes <= _minBytes) return bytes;
      final out = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );
      if (out.isEmpty || out.lengthInBytes >= bytes.lengthInBytes) {
        return bytes;
      }
      debugPrint(
          'COMPRESS: ${bytes.lengthInBytes} -> ${out.lengthInBytes} bytes');
      return out;
    } catch (e) {
      debugPrint('COMPRESS failed: $e');
      return bytes;
    }
  }
}
