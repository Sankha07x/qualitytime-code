import 'package:flutter/material.dart';
import '../../utils/settings/app_settings.dart';

Color _darker(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness - 0.15).clamp(0.0, 1.0)).toColor();
}

/// Gradient top of the profile page with photo, name and ID.
class ProfileHeader extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String uid;
  final VoidCallback onCopy;

  const ProfileHeader({
    super.key,
    required this.avatar,
    required this.name,
    required this.uid,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Color(AppSettings.accent.value);
    final top = MediaQuery.of(context).padding.top + kToolbarHeight;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, top + 8, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, _darker(accent)],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      child: Column(
        children: [
          avatar,
          const SizedBox(height: 16),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onCopy,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('@$uid',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_rounded,
                        size: 15, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded card with a small title above it.
class ProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ProfileSection({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2),
          ),
        ),
        Material(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}