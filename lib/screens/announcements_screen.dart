import 'package:flutter/material.dart';
import '../utils/dummy_data.dart';
import '../widgets/section_header.dart';
import '../widgets/announcement_tile.dart';

class AnnouncementsScreen extends StatelessWidget {
  static const route = '/announcements';
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
              title: 'Store Updates',
              subtitle: 'Announcements shown in-app (placeholder only).',
            ),
            ...DummyData.announcements.map(
              (a) => AnnouncementTile(announcement: a),
            ),
          ],
        ),
      ),
    );
  }
}
