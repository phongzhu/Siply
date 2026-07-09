class DrinkMenu {
  // Example: Map store id to menu
  static Map<String, List<Drink>> menus = {
    's1': [
      Drink(
        name: 'Classic Milk Tea',
        price: 65,
        tags: ['Best Seller'],
        imageUrl:
            'https://drive.google.com/uc?export=view&id=1aCOXsPO-zniRziwOALi3ax8RL8gYT_SI',
        description: 'Classic black tea with milk and pearls.',
        category: 'Milk Tea',
      ),
      Drink(
        name: 'Wintermelon Milk Tea',
        price: 70,
        tags: ['Classic'],
        imageUrl:
            'https://drive.google.com/uc?export=view&id=19jxWyBG_MZlhSm5t50UyONGP31fF5va5',
        description: 'Sweet wintermelon flavor with pearls.',
        category: 'Milk Tea',
      ),
      Drink(
        name: 'Fruit Tea',
        price: 70,
        tags: ['Fruit'],
        imageUrl:
            'https://images.pexels.com/photos/5945635/pexels-photo-5945635.jpeg?auto=compress&w=120&q=80',
        description: 'Refreshing fruit tea with real fruit bits.',
        category: 'Fruit Tea',
      ),
    ],
    // Add more store menus here as needed
  };

  static List<Drink> getMenuForStore(String storeId) {
    return menus[storeId] ??
        [
          Drink(
            name: 'Milk Tea',
            price: 60,
            tags: ['Classic'],
            imageUrl:
                'https://drive.google.com/uc?export=view&id=1aCOXsPO-zniRziwOALi3ax8RL8gYT_SI',
            description: 'Classic milk tea.',
            category: 'Milk Tea',
          ),
          Drink(
            name: 'Wintermelon Milk Tea',
            price: 70,
            tags: ['Classic'],
            imageUrl:
                'https://drive.google.com/uc?export=view&id=19jxWyBG_MZlhSm5t50UyONGP31fF5va5',
            description: 'Sweet wintermelon flavor with pearls.',
            category: 'Milk Tea',
          ),
          Drink(
            name: 'Fruit Tea',
            price: 70,
            tags: ['Fruit'],
            imageUrl:
                'https://images.pexels.com/photos/5945635/pexels-photo-5945635.jpeg?auto=compress&w=120&q=80',
            description: 'Refreshing fruit tea with real fruit bits.',
            category: 'Fruit Tea',
          ),
        ];
  }
}

class Drink {
  final String name;
  final int price;
  final List<String> tags;

  // NEW (required for your build)
  final String imageUrl;

  // NEW (for CoCo-style menu details)
  final String description;

  // NEW (for category-based menu like CoCo)
  final String category;

  const Drink({
    required this.name,
    required this.price,
    required this.tags,
    required this.imageUrl,
    required this.description,
    required this.category,
  });
}
