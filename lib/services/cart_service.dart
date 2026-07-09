import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cart.dart';

class CartService {
  final SupabaseClient client;
  final int userId;

  CartService({required this.client, required this.userId});

  Future<Cart?> getActiveCart(int storeId) async {
    final res = await client
        .from('carts')
        .select()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .eq('status', 'active')
        .maybeSingle();
    if (res == null) return null;
    return Cart.fromMap(res);
  }

  Future<Cart> createCart(int storeId) async {
    final res = await client
        .from('carts')
        .insert({'user_id': userId, 'store_id': storeId, 'status': 'active'})
        .select()
        .single();
    return Cart.fromMap(res);
  }

  Future<List<CartItem>> getCartItems(int cartId) async {
    final res = await client.from('cart_items').select().eq('cart_id', cartId);
    return (res as List).map((e) => CartItem.fromMap(e)).toList();
  }

  Future<Cart> getOrCreateActiveCart(int storeId) async {
    final existing = await getActiveCart(storeId);
    if (existing != null) return existing;
    return createCart(storeId);
  }

  Future<CartItem?> getCartItem({
    required int cartId,
    required int menuId,
    int? variantId,
  }) async {
    final q = client
        .from('cart_items')
        .select()
        .eq('cart_id', cartId)
        .eq('menu_id', menuId);

    final row = variantId == null
        ? await q.isFilter('variant_id', null).maybeSingle()
        : await q.eq('variant_id', variantId).maybeSingle();
    if (row == null) return null;
    return CartItem.fromMap(row);
  }

  Future<void> setCartItemQuantity({
    required int cartId,
    required int storeId,
    required int menuId,
    int? variantId,
    required int quantity,
    required double price,
  }) async {
    final existing = await getCartItem(
      cartId: cartId,
      menuId: menuId,
      variantId: variantId,
    );

    if (quantity <= 0) {
      if (existing != null) {
        await removeCartItem(existing.cartItemId);
      }
      return;
    }

    if (existing == null) {
      await client.from('cart_items').insert({
        'cart_id': cartId,
        'store_id': storeId,
        'menu_id': menuId,
        'variant_id': variantId,
        'quantity': quantity,
        'price': price,
      });
      return;
    }

    await client.from('cart_items').update({
      'quantity': quantity,
      'price': price,
    }).eq('cart_item_id', existing.cartItemId);
  }

  Future<void> incrementCartItem({
    required int cartId,
    required int storeId,
    required int menuId,
    int? variantId,
    required int delta,
    required double price,
  }) async {
    final existing = await getCartItem(
      cartId: cartId,
      menuId: menuId,
      variantId: variantId,
    );
    final nextQty = (existing?.quantity ?? 0) + delta;
    await setCartItemQuantity(
      cartId: cartId,
      storeId: storeId,
      menuId: menuId,
      variantId: variantId,
      quantity: nextQty,
      price: price,
    );
  }

  Future<void> removeCartItem(int cartItemId) async {
    await client.from('cart_items').delete().eq('cart_item_id', cartItemId);
  }

  Future<void> clearCart(int cartId) async {
    await client.from('cart_items').delete().eq('cart_id', cartId);
  }

  Future<void> abandonCart(int cartId) async {
    await client
        .from('carts')
        .update({'status': 'abandoned'})
        .eq('cart_id', cartId);
  }
}
