class StoreItem {
  final String id;
  final String name;
  final String city; // Baliuag / Pulilan / Bustos
  final String subtitle; // e.g., "Milk tea • 0.8 km"
  final double rating;
  final int etaMins; // estimated pickup time
  final bool hasVoucher;
  final int discountPercent; // 0 if none
  final String imageUrl; // URL for store image/logo/banner

  const StoreItem({
    required this.id,
    required this.name,
    required this.city,
    required this.subtitle,
    required this.rating,
    required this.etaMins,
    required this.hasVoucher,
    required this.discountPercent,
    required this.imageUrl,
  });
}

class StoreDummyData {
  static const cities = ['Baliuag', 'Pulilan', 'Bustos'];

  // Replace imageUrl with your own hosted images later (Supabase Storage, etc.)
  static const stores = <StoreItem>[
    StoreItem(
      id: 's1',
      name: 'Big Brew',
      city: 'Baliuag',
      subtitle: 'Milk tea • 0.7 km',
      rating: 4.6,
      etaMins: 12,
      hasVoucher: true,
      discountPercent: 20,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=17aHkMvNHT1mDs60wxXYQ-xl7o4toVIec',
    ),
    StoreItem(
      id: 's2',
      name: 'CoCo Fresh Tea & Juice',
      city: 'Baliuag',
      subtitle: 'Fruit tea • 1.3 km',
      rating: 4.5,
      etaMins: 18,
      hasVoucher: true,
      discountPercent: 15,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1Gl5Qf5hR339xdx0iPXU4_ew6ciopSEjm',
    ),
    StoreItem(
      id: 's3',
      name: 'Gong Cha',
      city: 'Pulilan',
      subtitle: 'Milk tea • 2.4 km',
      rating: 4.7,
      etaMins: 20,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1axIo9SJPv4DRAzMfSZTbgULfXkwTik5z',
    ),
    StoreItem(
      id: 's4',
      name: 'Dakasi',
      city: 'Bustos',
      subtitle: 'Milk tea • 3.1 km',
      rating: 4.4,
      etaMins: 22,
      hasVoucher: true,
      discountPercent: 10,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1c7TF6Cdq8vD1novjG_u9kH41_PvbKRmZ',
    ),
    StoreItem(
      id: 's5',
      name: 'Fruity Lemon (SM Baliwag)',
      city: 'Baliuag',
      subtitle: 'Lemonade • 0.9 km',
      rating: 4.3,
      etaMins: 14,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1A0iDYwU0IZeqjsHyb0vqLvQXEHZEdRtA',
    ),
    // ===================== BALIUAG =====================
    StoreItem(
      id: 's6',
      name: 'Chatime',
      city: 'Baliuag',
      subtitle: 'Milk tea • 1.1 km',
      rating: 4.6,
      etaMins: 16,
      hasVoucher: true,
      discountPercent: 10,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=11cB9md8Lq0H9nqdiXvdS3YPHr9jDx-x-',
    ),
    StoreItem(
      id: 's7',
      name: 'Macao Imperial Tea',
      city: 'Baliuag',
      subtitle: 'Cream cheese tea • 1.9 km',
      rating: 4.7,
      etaMins: 19,
      hasVoucher: true,
      discountPercent: 15,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1smqzD3e9Zw3fMuC55x6qPx_XI9_KWaS9',
    ),
    StoreItem(
      id: 's8',
      name: 'Happy Lemon',
      city: 'Baliuag',
      subtitle: 'Cheese tea • 2.3 km',
      rating: 4.5,
      etaMins: 21,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl: 'https://www.facebook.com/HappyLemonPh/',
    ),
    StoreItem(
      id: 's9',
      name: 'Zagu',
      city: 'Baliuag',
      subtitle: 'Pearl shake • 0.8 km',
      rating: 4.2,
      etaMins: 13,
      hasVoucher: true,
      discountPercent: 20,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1YeffRiG29IdmGlYFhWbXpI6D0CHVis_f',
    ),
    StoreItem(
      id: 's10',
      name: 'Coffee Project',
      city: 'Baliuag',
      subtitle: 'Iced coffee • 2.7 km',
      rating: 4.4,
      etaMins: 24,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1jMmmIb0Cqxq1ZkWmK4BjuN2ICLzYAOaR',
    ),

    // ===================== PULILAN =====================
    StoreItem(
      id: 's11',
      name: 'Serenitea',
      city: 'Pulilan',
      subtitle: 'Milk tea • 1.0 km',
      rating: 4.4,
      etaMins: 15,
      hasVoucher: true,
      discountPercent: 10,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1yuJvcbSFL4iq1nnqpzqysKspiYc0meiG',
    ),
    StoreItem(
      id: 's12',
      name: 'Infinitea',
      city: 'Pulilan',
      subtitle: 'Fruit tea • 1.8 km',
      rating: 4.3,
      etaMins: 17,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1ZvYHUzA1BD5JgdliK1oZYxIb4LcJxNHG',
    ),
    StoreItem(
      id: 's13',
      name: 'Tea Talk',
      city: 'Pulilan',
      subtitle: 'Milk tea • 2.2 km',
      rating: 4.5,
      etaMins: 19,
      hasVoucher: true,
      discountPercent: 15,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1t94X351Wy2ynkb4U5ZBL0RHKWVAEgJXe',
    ),
    StoreItem(
      id: 's14',
      name: 'Brewed Awakening',
      city: 'Pulilan',
      subtitle: 'Cold brew • 3.0 km',
      rating: 4.2,
      etaMins: 23,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1aTDwSoZitNLcrd_CCL12I7cAD8hV1qwL',
    ),

    // ===================== BUSTOS =====================
    StoreItem(
      id: 's15',
      name: 'Tea Talk Bustos',
      city: 'Bustos',
      subtitle: 'Milk tea • 0.6 km',
      rating: 4.4,
      etaMins: 11,
      hasVoucher: true,
      discountPercent: 10,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1t94X351Wy2ynkb4U5ZBL0RHKWVAEgJXe',
    ),
    StoreItem(
      id: 's16',
      name: 'Mr. Shake',
      city: 'Bustos',
      subtitle: 'Fruit shake • 1.4 km',
      rating: 4.1,
      etaMins: 15,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=12ioKIcS2d8UAtbgh4-U6R2p6ijdLK9JA',
    ),
    StoreItem(
      id: 's17',
      name: 'Cool Beans Café',
      city: 'Bustos',
      subtitle: 'Iced coffee • 2.6 km',
      rating: 4.5,
      etaMins: 21,
      hasVoucher: true,
      discountPercent: 15,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=19AAB90Ooi6TS4yHWUQ73QDVUHADAkiuo',
    ),
    StoreItem(
      id: 's18',
      name: 'Daily Dose Coffee',
      city: 'Bustos',
      subtitle: 'Cold brew • 3.2 km',
      rating: 4.3,
      etaMins: 25,
      hasVoucher: false,
      discountPercent: 0,
      imageUrl:
          'https://drive.google.com/uc?export=view&id=1vLPXEVZlDLmHed1HqIJLfJ0kwdh-wpq7',
    ),
  ];
}
