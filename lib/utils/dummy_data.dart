import '../models/drink.dart';
import '../models/voucher.dart';
import '../models/announcement.dart';

class DummyData {
  // CoCo-style categories:
  // Milk Tea, Fruit Tea, Fresh Tea, Cream & Latte, Juice, Chocolate, Slush, Coffee
  static final drinks = <Drink>[
    // ---------------- MILK TEA ----------------
    Drink(
      name: 'CoCo Milk Tea',
      price: 95,
      tags: ['Classic'],
      category: 'Milk Tea',
      description:
          'Signature black-tea milk tea base. Smooth, creamy, and balanced.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/CoCo-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'Pearl Milk Tea',
      price: 100,
      tags: ['Best Seller'],
      category: 'Milk Tea',
      description: 'Signature milk tea topped with chewy black pearls (boba).',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Pearl-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'Panda Milk Tea',
      price: 100,
      tags: ['Popular'],
      category: 'Milk Tea',
      description:
          'Milk tea with both black & white pearls for a fun chewy mix.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Panda-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'Grass Jelly Milk Tea',
      price: 100,
      tags: ['Toppings'],
      category: 'Milk Tea',
      description:
          'Milk tea with grass jelly for a bouncy, refreshing texture.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Grass-Jelly-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'White Pearl Milk Tea',
      price: 100,
      tags: ['Chewy'],
      category: 'Milk Tea',
      description:
          'Milk tea paired with white pearls for a lighter chewy bite.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/White-Pearl-Milk-Tea-300x300.png',
    ),
    Drink(
      name: '2 Ladies Milk Tea',
      price: 110,
      tags: ['Popular'],
      category: 'Milk Tea',
      description:
          'Signature milk tea with pearls and pudding — a crowd favorite combo.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/2-Ladies-Milk-Tea-300x300.png',
    ),
    Drink(
      name: '3 Buddies Milk Tea',
      price: 120,
      tags: ['Popular', 'Toppings'],
      category: 'Milk Tea',
      description:
          'Loaded toppings: pearls, pudding, and grass jelly in one drink.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/3-Buddies-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'Taro Milk Tea',
      price: 110,
      tags: ['Creamy'],
      category: 'Milk Tea',
      description:
          'Milk tea blended with taro flavor for a rich and creamy sip.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Taro-Milk-Tea-300x300.png',
    ),
    Drink(
      name: 'Salty Cream Milk Tea',
      price: 110,
      tags: ['Salty Cream'],
      category: 'Milk Tea',
      description: 'Classic milk tea topped with CoCo’s signature salty cream.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Salty-Cream-Milk-Tea-300x300.png',
    ),

    // ---------------- FRUIT TEA ----------------
    Drink(
      name: 'Passion Fruit Tea Burst',
      price: 110,
      tags: ['Best Seller'],
      category: 'Fruit Tea',
      description: 'Passion fruit with green tea plus pearl & coconut jelly.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Passion-Fruit-Tea-Burst-300x300.png',
    ),
    Drink(
      name: 'Lemon Black Tea',
      price: 90,
      tags: ['Refreshing'],
      category: 'Fruit Tea',
      description: 'A bright lemon twist mixed with smooth black tea.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Lemon-Black-Tea-300x300.png',
    ),
    Drink(
      name: 'Lemon Dunk',
      price: 110,
      tags: ['Fresh Lemon'],
      category: 'Fruit Tea',
      description:
          'Whole lemon squeezed into jasmine green tea for a bold citrus tea.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Lemon-Dunk-300x300.png',
    ),
    Drink(
      name: 'Passion Fruit Green or Mountain Tea',
      price: 100,
      tags: ['Light'],
      category: 'Fruit Tea',
      description:
          'Passion fruit with a clean tea base (green or mountain tea).',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Passion-Fruit-Green-or-Mountain-Tea-300x300.png',
    ),
    Drink(
      name: 'Grapefruit & Orange Tea',
      price: 110,
      tags: ['Citrus'],
      category: 'Fruit Tea',
      description:
          'A citrus blend of grapefruit and orange with tea for a zesty finish.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Grapefruit-and-Orange-Tea-300x300.png',
    ),
    Drink(
      name: 'Orange Mountain Tea',
      price: 110,
      tags: ['Citrus'],
      category: 'Fruit Tea',
      description: 'Orange + mountain tea for a clean, fruity refreshment.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Orange-Mountain-Tea-300x300.png',
    ),

    // ---------------- FRESH TEA ----------------
    Drink(
      name: 'Honey Mountain Tea',
      price: 100,
      tags: ['Honey'],
      category: 'Fresh Tea',
      description:
          'Light mountain tea sweetened with honey for a soothing tea.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Honey-Mountain-Tea-300x300.png',
    ),

    // ---------------- CREAM & LATTE ----------------
    Drink(
      name: 'Black Tea Latte',
      price: 115,
      tags: ['Latte'],
      category: 'Cream & Latte',
      description:
          'Black tea latte with a creamy finish — smooth and easy to drink.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Black-Tea-Latte-300x300.png',
    ),
    Drink(
      name: 'Winter Melon Latte',
      price: 115,
      tags: ['Latte'],
      category: 'Cream & Latte',
      description: 'Creamy winter melon latte — sweet, mellow, and comforting.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Winter-Melon-Latte-300x300.png',
    ),
    Drink(
      name: 'Matcha Tea Latte',
      price: 125,
      tags: ['Matcha'],
      category: 'Cream & Latte',
      description: 'Premium matcha blended into a creamy latte base.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Matcha-Tea-Latte-300x300.png',
    ),
    Drink(
      name: 'Taro Latte',
      price: 125,
      tags: ['Taro'],
      category: 'Cream & Latte',
      description:
          'Taro blended latte for a rich, sweet, creamy taro experience.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Taro-Latte-300x300.png',
    ),

    // ---------------- JUICE ----------------
    Drink(
      name: 'Green Tea Yakult',
      price: 110,
      tags: ['Yakult'],
      category: 'Juice',
      description:
          'Green tea mixed with Yakult for a sweet-tangy probiotic drink.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Green-Tea-Yakult-300x300.png',
    ),
    Drink(
      name: 'Lemon Yakult',
      price: 110,
      tags: ['Yakult', 'Citrus'],
      category: 'Juice',
      description: 'Yakult with lemon notes — tangy, refreshing, and light.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Lemon-Yakult-300x300.png',
    ),
    Drink(
      name: 'Honey Lemon with Aloe',
      price: 110,
      tags: ['Aloe'],
      category: 'Juice',
      description:
          'Honey lemon drink with aloe for a soothing, cooling texture.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Honey-Lemon-with-Aloe-300x300.png',
    ),
    Drink(
      name: 'Winter Melon with Grass Jelly',
      price: 105,
      tags: ['Grass Jelly'],
      category: 'Juice',
      description: 'Winter melon drink topped with grass jelly for extra chew.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Winter-Melon-with-Grass-Jelly-300x300.png',
    ),

    // ---------------- CHOCOLATE ----------------
    Drink(
      name: 'Chocolate with Pearl',
      price: 115,
      tags: ['Chocolate'],
      category: 'Chocolate',
      description: 'Chocolate drink with chewy pearls for a dessert-like sip.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Chocolate-with-Pearl-300x300.png',
    ),

    // ---------------- SLUSH ----------------
    Drink(
      name: 'Passion Fruit Slush',
      price: 120,
      tags: ['Icy'],
      category: 'Slush',
      description: 'Icy passion fruit slush — fruity and ultra refreshing.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Passion-Fruit-Slush-300x300.png',
    ),
    Drink(
      name: 'Taro Slush',
      price: 120,
      tags: ['Icy', 'Taro'],
      category: 'Slush',
      description: 'Creamy taro blended into an icy slush texture.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Taro-Slush-1-300x300.png',
    ),
    Drink(
      name: 'Matcha Slush with Salty Cream',
      price: 135,
      tags: ['Matcha', 'Salty Cream'],
      category: 'Slush',
      description: 'Icy matcha slush topped with signature salty cream.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2019/01/Matcha-Slush-with-Salty-Cream-300x300.png',
    ),

    // ---------------- COFFEE ----------------
    Drink(
      name: 'CoCo Coffee',
      price: 115,
      tags: ['Coffee'],
      category: 'Coffee',
      description: 'CoCo-style iced coffee — smooth, milky, and balanced.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2020/04/CoCo-Coffee-300x300.png',
    ),
    Drink(
      name: 'CoCo Coffee with Pearl',
      price: 125,
      tags: ['Coffee', 'Pearl'],
      category: 'Coffee',
      description: 'Iced coffee with pearls for a sweet chewy coffee drink.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2020/04/CoCo-Coffee-with-Pearl-300x300.png',
    ),
    Drink(
      name: 'CoCo Black Coffee',
      price: 105,
      tags: ['Strong'],
      category: 'Coffee',
      description: 'Clean black iced coffee for a stronger coffee taste.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2020/04/CoCo-Black-Coffee-300x300.png',
    ),
    Drink(
      name: 'Salty Cream Coffee',
      price: 130,
      tags: ['Salty Cream'],
      category: 'Coffee',
      description: 'Iced coffee topped with signature salty cream.',
      imageUrl:
          'https://coco-tea.ph/wp-content/uploads/2020/04/Salty-Cream-Coffee-300x300.png',
    ),
  ];

  static final vouchers = <Voucher>[
    Voucher(
      title: '₱20 OFF',
      description: 'Min. spend ₱150. App exclusive.',
      code: 'SIPLY20',
    ),
    Voucher(
      title: 'Buy 1 Get 10% OFF 2nd',
      description: 'Valid for selected drinks.',
      code: 'B1G10',
    ),
    Voucher(
      title: 'Free Upsize',
      description: 'Use once per account.',
      code: 'UPSIZE',
    ),
  ];

  static final announcements = <Announcement>[
    Announcement(
      title: 'New Flavor Drop!',
      body: 'Try our Matcha Tea Latte—now available in all branches.',
    ),
    Announcement(
      title: 'Maintenance Notice',
      body: 'Some features may be unavailable tonight 10PM–12AM.',
    ),
    Announcement(
      title: 'Rewards Update',
      body: 'More vouchers are coming this month. Stay tuned!',
    ),
  ];
}
