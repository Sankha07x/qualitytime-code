import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/auth/phone_auth_service.dart';
import '../../core/auth/profile_service.dart';
import 'dart:typed_data';
import '../../utils/user_avatar.dart';
import '../../utils/photo_viewer.dart';
import '../../utils/photo_editor_screen.dart';

/// Edit own photo, name and ID. Pops with true when the ID was changed.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = ProfileService();
  final _nameCtrl = TextEditingController();
  MyProfile? _me;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final p = await _service.load();
      if (!mounted || p == null) return;
      setState(() {
        _me = p;
        _nameCtrl.text = p.name;
      });
    } catch (_) {
      _toast("Couldn't load your profile");
    }
  }

  void _photoMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto();
              },
            ),
if (_me?.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBig();
                },
              ),
            if (_me?.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Edit current photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editCurrent();
                },
              ),
            if (_me?.photoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _removePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

void _openBig() {
    final url = _me?.photoUrl;
    if (url == null || url.isEmpty) {
      _photoMenu();
      return;
    }
    showPhotoViewer(context, url, title: _me?.name);
  }

  /// Opens the editor on the photo I already have.
  Future<void> _editCurrent() async {
    final url = _me?.photoUrl;
    if (url == null || _busy) return;
    try {
      final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
      if (!mounted) return;
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (_) =>
              PhotoEditorScreen(bytes: data.buffer.asUint8List()),
        ),
      );
      if (bytes == null || !mounted) return;
      setState(() => _busy = true);
      final newUrl = await _service.uploadPhoto(bytes);
      if (!mounted) return;
      setState(() => _me = _me?.copyWith(photoUrl: newUrl));
    } catch (_) {
      _toast("Couldn't update the photo");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (x == null) return;
      setState(() => _busy = true);
      final raw = await x.readAsBytes();
      if (!mounted) return;
      final bytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => PhotoEditorScreen(bytes: raw)),
      );
      if (bytes == null) return;
      final url = await _service.uploadPhoto(bytes);
      if (!mounted) return;
      setState(() => _me = _me?.copyWith(photoUrl: url));
    } catch (_) {
      _toast("Couldn't update the photo");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.removePhoto();
      if (mounted) setState(() => _me = _me?.copyWith(clearPhoto: true));
    } catch (_) {
      _toast("Couldn't remove the photo");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveName() async {
    final n = _nameCtrl.text.trim();
    if (n.isEmpty || n.length > 30) {
      _toast('Name must be 1 to 30 characters');
      return;
    }
    if (n == _me?.name) return;
    setState(() => _busy = true);
    try {
      await _service.updateName(n);
      if (!mounted) return;
      setState(() => _me = _me?.copyWith(name: n));
      FocusScope.of(context).unfocus();
      _toast('Name saved');
    } catch (_) {
      _toast("Couldn't save the name");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeId() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change your ID'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You can do this only once. Friends who saved your old ID must add the new one.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: 'new-id',
                helperText: 'a-z, 0-9, - and _ (3 to 20)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty) return;
    setState(() => _busy = true);
    final err = await _service.changeUid(value);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(err);
      return;
    }
    _toast('ID changed');
    Navigator.of(context).pop(true);
  }

  void _signOut() {
    final auth = PhoneAuthService();
    Navigator.of(context).pop();
    auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: me == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _openBig,
                    child: Stack(
                      children: [
                        UserAvatar(
                          name: me.name,
                          photoUrl: me.photoUrl,
                          radius: 56,
                        ),
                        if (_busy)
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black38,
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: _photoMenu,
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: scheme.primary,
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _saveName(),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      tooltip: 'Save name',
                      onPressed: _saveName,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    title: const Text('Your ID'),
                    subtitle: SelectableText(me.uid),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy ID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: me.uid));
                            _toast('ID copied');
                          },
                        ),
                        if (!me.uidChanged)
                          TextButton(
                            onPressed: _busy ? null : _changeId,
                            child: const Text('Change'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (me.uidChanged)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 4),
                    child: Text(
                      'Your ID was already changed once.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text(
                    'Sign out',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
    );
  }
}