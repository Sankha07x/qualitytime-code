import 'package:flutter/material.dart';
import 'contact_controller.dart';
import '../../utils/user_avatar.dart';

class FriendRequestsScreen extends StatelessWidget {
  final ContactController contactController;

  const FriendRequestsScreen({super.key, required this.contactController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friend requests')),
      body: ValueListenableBuilder<List<Map<String, String>>>(
        valueListenable: contactController.incoming,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return const Center(child: Text('No requests.'));
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final r = list[i];
              final photo = contactController.photos.value[r['uid']];
              return ListTile(
                leading: UserAvatar(
                  name: r['name'] ?? '?',
                  photoUrl: (photo == null || photo.isEmpty) ? null : photo,
                ),
                title: Text(r['name'] ?? ''),
                subtitle: Text(r['uid'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decline',
                      icon: const Icon(Icons.close, color: Colors.redAccent),
                      onPressed: () =>
                          contactController.declineRequest(r['id']!),
                    ),
                    IconButton(
                      tooltip: 'Accept',
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () =>
                          contactController.acceptRequest(r['id']!),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}