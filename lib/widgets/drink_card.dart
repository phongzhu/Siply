import 'package:flutter/material.dart';
import '../models/drink.dart';
import '../utils/app_theme.dart';

class DrinkCard extends StatelessWidget {
  final Drink drink;
  final VoidCallback onAdd;

  const DrinkCard({super.key, required this.drink, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              drink.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: drink.tags.take(2).map((t) {
                return Chip(
                  label: Text(t, style: const TextStyle(fontSize: 11)),
                  backgroundColor: AppTheme.primary.withOpacity(0.08),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const Spacer(),
            Row(
              children: [
                Text(
                  '₱${drink.price}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle),
                  tooltip: 'Add (UI only)',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
