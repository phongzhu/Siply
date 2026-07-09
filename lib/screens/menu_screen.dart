import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/dummy_data.dart';
import '../models/drink.dart';

class MenuScreen extends StatefulWidget {
  static const route = '/menu';
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _selectedCategory = 'Milk Tea';

  List<String> get _categories {
    final set = <String>{};
    for (final d in DummyData.drinks) {
      set.add(d.category);
    }
    // CoCo-like ordering
    const preferred = [
      'Milk Tea',
      'Fruit Tea',
      'Fresh Tea',
      'Cream & Latte',
      'Juice',
      'Chocolate',
      'Slush',
      'Coffee',
    ];
    final ordered = <String>[];
    for (final p in preferred) {
      if (set.contains(p)) ordered.add(p);
    }
    for (final c in set) {
      if (!ordered.contains(c)) ordered.add(c);
    }
    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final drinks = DummyData.drinks
        .where((d) => d.category == _selectedCategory)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(title: const Text('Menu'), centerTitle: false),
      body: SafeArea(
        child: Column(
          children: [
            // Category chips (CoCo-like browsing)
            SizedBox(
              height: 54,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) {
                  final c = _categories[i];
                  final selected = c == _selectedCategory;
                  return ChoiceChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : AppTheme.primary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primary,
                    backgroundColor: Colors.white,
                    onSelected: (_) => setState(() => _selectedCategory = c),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.primary
                          : Colors.grey.withOpacity(0.25),
                      width: 1.25,
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: _categories.length,
              ),
            ),

            // List of drinks
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                itemCount: drinks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final d = drinks[index];
                  return _DrinkCard(
                    drink: d,
                    onTap: () {
                      // Hook this into your item details / order flow later
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${d.name} selected (UI-only).'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrinkCard extends StatelessWidget {
  final Drink drink;
  final VoidCallback onTap;

  const _DrinkCard({required this.drink, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 76,
                    height: 76,
                    color: Colors.grey[100],
                    child: Image.network(
                      drink.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + price (no overflow)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              drink.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '₱${drink.price}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Text(
                        drink.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Tags (wrap avoids overflow)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: drink.tags.take(3).map((t) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppTheme.primary.withOpacity(0.15),
                              ),
                            ),
                            child: Text(
                              t,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: AppTheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
