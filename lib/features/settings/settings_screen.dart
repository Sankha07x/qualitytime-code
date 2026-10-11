import 'package:flutter/material.dart';
import 'customize_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Customize'),
              subtitle: const Text('Colour, wallpaper, calling tone'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomizeScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}