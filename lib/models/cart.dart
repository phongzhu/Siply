class Cart {
  final int cartId;
  final int userId;
  final int storeId;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Cart({
    required this.cartId,
    required this.userId,
    required this.storeId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Cart.fromMap(Map<String, dynamic> map) {
    return Cart(
      cartId: (map['cart_id'] as num).toInt(),
      userId: (map['user_id'] as num).toInt(),
      storeId: (map['store_id'] as num).toInt(),
      status: map['status'] ?? 'active',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}

class CartItem {
  final int cartItemId;
  final int cartId;
  final int storeId;
  final int menuId;
  final int? variantId;
  final int quantity;
  final double price;
  final DateTime createdAt;
  final DateTime updatedAt;

  CartItem({
    required this.cartItemId,
    required this.cartId,
    required this.storeId,
    required this.menuId,
    this.variantId,
    required this.quantity,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      cartItemId: (map['cart_item_id'] as num).toInt(),
      cartId: (map['cart_id'] as num).toInt(),
      storeId: (map['store_id'] as num).toInt(),
      menuId: (map['menu_id'] as num).toInt(),
      variantId: map['variant_id'] != null
          ? (map['variant_id'] as num).toInt()
          : null,
      quantity: (map['quantity'] as num).toInt(),
      price: double.parse(map['price'].toString()),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }
}
