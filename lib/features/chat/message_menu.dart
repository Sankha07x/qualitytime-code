import 'package:flutter/material.dart';

/// Long-press menu. Returns 'copy', 'me', 'all', or null.
Future<String?> showMessageMenu(
  BuildContext context, {
  required bool canCopy,
  required bool mine,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canCopy)
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete for me'),
            onTap: () => Navigator.pop(ctx, 'me'),
          ),
          if (mine)
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined,
                  color: Colors.redAccent),
              title: const Text('Delete for everyone',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
        ],
      ),
    ),
  );
}