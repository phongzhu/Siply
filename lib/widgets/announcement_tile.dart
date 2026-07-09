import 'package:flutter/material.dart';
import '../models/announcement.dart';

class AnnouncementTile extends StatelessWidget {
  final Announcement announcement;
  const AnnouncementTile({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          announcement.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(announcement.body),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
