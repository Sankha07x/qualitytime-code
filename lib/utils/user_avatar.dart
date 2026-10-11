import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Google profile photos carry a tiny size tag (=s96-c). Ask for 512 px
/// instead. One size everywhere, so one disk-cache entry works offline too.
String hiResPhoto(String url, {int size = 512}) {
  if (!url.contains('googleusercontent.com')) return url;
  final tail = RegExp(r'=s\d+(-c)?$');
  if (tail.hasMatch(url)) return url.replaceFirst(tail, '=s$size-c');
  final mid = RegExp(r'/s\d+-c/');
  if (mid.hasMatch(url)) return url.replaceFirst(mid, '/s$size-c/');
  return url;
}

class UserAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double radius;

  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
  });

  Widget _letter() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5EEAD4), Color(0xFF0D9488)],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = radius * 2;
    final has = photoUrl != null && photoUrl!.isNotEmpty;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = (d * dpr).round().clamp(96, 1024).toInt();
    return SizedBox(
      width: d,
      height: d,
      child: ClipOval(
        child: has
            ? CachedNetworkImage(
                imageUrl: hiResPhoto(photoUrl!),
                width: d,
                height: d,
                fit: BoxFit.cover,
                memCacheWidth: px,
                filterQuality: FilterQuality.high,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (_, __) => _letter(),
                errorWidget: (_, __, ___) => _letter(),
              )
            : _letter(),
      ),
    );
  }
}