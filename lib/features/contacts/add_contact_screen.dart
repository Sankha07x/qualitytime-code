import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'contact_controller.dart';
import '../../utils/user_avatar.dart';

class AddContactScreen extends StatefulWidget {
  final ContactController contactController;

  const AddContactScreen({super.key, required this.contactController});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _uidController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final t = d?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => _uidController.text = t);
  }

  Future<void> _submit() async {
    final uid = _uidController.text.trim();
    if (uid.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    Map<String, dynamic>? profile;
    try {
      profile = await widget.contactController.lookupUid(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not check. Are you online?';
      });
      return;
    }

    if (profile == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No user found with that ID.';
      });
      return;
    }

    final err = await widget.contactController.sendFriendRequest(uid);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = err;
      });
      return;
    }
    setState(() {
      _isLoading = false;
      _uidController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend request sent')),
    );
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  Widget _header(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 10,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cc = widget.contactController;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Friend')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.primaryContainer.withOpacity(0.4),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.primary,
                      child: Icon(Icons.person_add_alt_1,
                          color: scheme.onPrimary),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Find a friend\nEnter their unique ID',
                        style: TextStyle(fontSize: 15, height: 1.3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _uidController,
                  autocorrect: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surface.withOpacity(0.85),
                    hintText: 'amber-falcon-17',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(Icons.content_paste),
                      onPressed: _paste,
                    ),
                    errorText: _errorMessage,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send friend request'),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: cc.incoming,
            builder: (context, list, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header('Pending requests', list.length),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No pending requests.'),
                  ),
                for (final r in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: UserAvatar(
                        name: r['name'] ?? '?',
                        photoUrl: () {
                          final p = cc.photos.value[r['uid']];
                          return (p == null || p.isEmpty) ? null : p;
                        }(),
                      ),
                      title: Text(r['name'] ?? ''),
                      subtitle: Text(r['uid'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Decline',
                            icon: const Icon(Icons.close,
                                color: Colors.redAccent),
                            onPressed: () => cc.declineRequest(r['id']!),
                          ),
                          IconButton(
                            tooltip: 'Accept',
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => cc.acceptRequest(r['id']!),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<List<Map<String, String>>>(
            valueListenable: cc.sent,
            builder: (context, list, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header('Request sent', list.length),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('No sent requests.'),
                  ),
                for (final r in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: UserAvatar(
                        name: r['name'] ?? '?',
                        photoUrl: () {
                          final p = cc.photos.value[r['uid']];
                          return (p == null || p.isEmpty) ? null : p;
                        }(),
                      ),
                      title: Text(r['name'] ?? ''),
                      subtitle: const Text('Waiting for reply'),
                      trailing: TextButton(
                        onPressed: () => cc.cancelRequest(r['id']!),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}