import 'package:flutter/material.dart';
import '../../utils/settings/chat_prefs.dart';

/// Asks for the chat PIN. Returns true when it is right.
Future<bool> askChatPin(BuildContext context,
    {String title = 'Enter PIN'}) async {
  final c = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(counterText: '', errorText: err),
          onChanged: (v) {
            if (v.length == 4) {
              if (ChatPrefs.checkPin(v)) {
                Navigator.pop(ctx, true);
              } else {
                c.clear();
                set(() => err = 'Wrong PIN');
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
  return ok == true;
}

/// First time: the user makes a 4-digit PIN. Returns true when saved.
Future<bool> createChatPin(BuildContext context) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Create a 4-digit PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            TextField(
              controller: b,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                  labelText: 'Repeat PIN', errorText: err),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (a.text.length != 4 || int.tryParse(a.text) == null) {
                set(() => err = 'Use 4 digits');
              } else if (a.text != b.text) {
                set(() => err = 'PINs do not match');
              } else {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    await ChatPrefs.setPin(a.text);
    return true;
  }
  return false;
}

/// Lock on (makes a PIN the first time) or off (asks the PIN).
Future<void> toggleChatLock(BuildContext context, String key, bool on) async {
  if (on) {
    if (!ChatPrefs.hasPin && !await createChatPin(context)) return;
    await ChatPrefs.setLocked(key, true);
  } else {
    if (!await askChatPin(context, title: 'Enter PIN to unlock')) return;
    await ChatPrefs.setLocked(key, false);
  }
}

/// Shown instead of a locked chat.
class LockedChatView extends StatefulWidget {
  final VoidCallback onUnlock;
  const LockedChatView({super.key, required this.onUnlock});

  @override
  State<LockedChatView> createState() => _LockedChatViewState();
}

class _LockedChatViewState extends State<LockedChatView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    final ok = await askChatPin(context);
    if (ok && mounted) widget.onUnlock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locked chat')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 64),
            const SizedBox(height: 12),
            const Text('This chat is locked'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _unlock, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}