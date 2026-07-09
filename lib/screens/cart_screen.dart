import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/paymongo_service.dart';
import '../utils/app_theme.dart';
import '../widgets/section_header.dart';
import '../widgets/primary_button.dart';
import 'paymongo_checkout_screen.dart';

/// =======================================================
/// CART ARGS (passed from ViewStoreScreen)
/// =======================================================
class CartArgs {
  final int storeId;
  final String storeName;

  /// menu_id -> qty
  final Map<int, int> cart;

  /// Full menu list (so we can look up names/prices/images)
  final List<StoreMenuItemDto> menu;
  final List<CartSelectedItemDto> selectedItems;

  CartArgs({
    required this.storeId,
    required this.storeName,
    required this.cart,
    required this.menu,
    this.selectedItems = const [],
  });
}

class CartSelectedItemDto {
  final int menuId;
  final int? variantId;
  final String? sizeLabel;
  final int qty;
  final double unitPrice;
  final List<CartAddonDto> addons;
  final String name;
  final String? imageUrl;

  const CartSelectedItemDto({
    required this.menuId,
    required this.qty,
    required this.unitPrice,
    required this.name,
    this.addons = const [],
    this.variantId,
    this.sizeLabel,
    this.imageUrl,
  });
}

class CartAddonDto {
  final int menuId;
  final String name;
  final double unitPrice;
  final int qty;

  const CartAddonDto({
    required this.menuId,
    required this.name,
    required this.unitPrice,
    required this.qty,
  });
}

/// Minimal DTO (Cart needs only a few fields)
class StoreMenuItemDto {
  final int menuId;
  final String name;
  final String? imageUrl; // FULL public URL already
  final num price;

  StoreMenuItemDto({
    required this.menuId,
    required this.name,
    required this.price,
    this.imageUrl,
  });
}

/// =======================================================
/// Voucher DTOs (from your tables)
/// =======================================================
class VoucherTargetDto {
  final String targetType; // all_items, category, menu_item
  final int? categoryId;
  final int? menuId;

  VoucherTargetDto({required this.targetType, this.categoryId, this.menuId});

  factory VoucherTargetDto.fromMap(Map<String, dynamic> m) => VoucherTargetDto(
    targetType: (m['target_type'] ?? '').toString(),
    categoryId: (m['category_id'] as num?)?.toInt(),
    menuId: (m['menu_id'] as num?)?.toInt(),
  );
}

class BogoRuleDto {
  final int ruleId;

  final String buyType; // menu_item/category
  final int? buyMenuId;
  final int? buyCategoryId;
  final int buyQty;

  final String getType; // menu_item/category
  final int? getMenuId;
  final int? getCategoryId;
  final int getQty;

  final double getDiscountPercent; // 1-100

  BogoRuleDto({
    required this.ruleId,
    required this.buyType,
    required this.buyMenuId,
    required this.buyCategoryId,
    required this.buyQty,
    required this.getType,
    required this.getMenuId,
    required this.getCategoryId,
    required this.getQty,
    required this.getDiscountPercent,
  });

  factory BogoRuleDto.fromMap(Map<String, dynamic> m) => BogoRuleDto(
    ruleId: (m['rule_id'] as num).toInt(),
    buyType: (m['buy_type'] ?? '').toString(),
    buyMenuId: (m['buy_menu_id'] as num?)?.toInt(),
    buyCategoryId: (m['buy_category_id'] as num?)?.toInt(),
    buyQty: ((m['buy_qty'] as num?) ?? 1).toInt(),
    getType: (m['get_type'] ?? '').toString(),
    getMenuId: (m['get_menu_id'] as num?)?.toInt(),
    getCategoryId: (m['get_category_id'] as num?)?.toInt(),
    getQty: ((m['get_qty'] as num?) ?? 1).toInt(),
    getDiscountPercent: ((m['get_discount_percent'] as num?) ?? 100).toDouble(),
  );
}

class StoreVoucherDto {
  final int voucherId;
  final int storeId;
  final String code;
  final String? title;
  final String? details;

  final String voucherType; // discount, b1t1, bogo

  // discount
  final String? discountType; // percent, fixed
  final double? discountValue;
  final double minSpend;
  final double? maxDiscount;

  // b1t1
  final int? buyMenuId;
  final int? freeMenuId;
  final int buyQuantity;
  final int freeQuantity;

  final List<VoucherTargetDto> targets;
  final List<BogoRuleDto> bogoRules;

  StoreVoucherDto({
    required this.voucherId,
    required this.storeId,
    required this.code,
    required this.voucherType,
    required this.minSpend,
    required this.buyQuantity,
    required this.freeQuantity,
    required this.targets,
    required this.bogoRules,
    this.title,
    this.details,
    this.discountType,
    this.discountValue,
    this.maxDiscount,
    this.buyMenuId,
    this.freeMenuId,
  });

  factory StoreVoucherDto.fromMap(Map<String, dynamic> m) {
    final t =
        (m['store_voucher_targets'] as List?)
            ?.map(
              (e) =>
                  VoucherTargetDto.fromMap((e as Map).cast<String, dynamic>()),
            )
            .toList() ??
        const <VoucherTargetDto>[];

    final r =
        (m['store_voucher_bogo_rules'] as List?)
            ?.map(
              (e) => BogoRuleDto.fromMap((e as Map).cast<String, dynamic>()),
            )
            .toList() ??
        const <BogoRuleDto>[];

    return StoreVoucherDto(
      voucherId: (m['voucher_id'] as num).toInt(),
      storeId: (m['store_id'] as num).toInt(),
      code: (m['code'] ?? '').toString(),
      title: m['title']?.toString(),
      details: m['details']?.toString(),
      voucherType: (m['voucher_type'] ?? 'discount').toString(),
      discountType: m['discount_type']?.toString(),
      discountValue: (m['discount_value'] as num?)?.toDouble(),
      minSpend: (m['min_spend'] as num?)?.toDouble() ?? 0.0,
      maxDiscount: (m['max_discount'] as num?)?.toDouble(),
      buyMenuId: (m['buy_menu_id'] as num?)?.toInt(),
      freeMenuId: (m['free_menu_id'] as num?)?.toInt(),
      buyQuantity: (m['buy_quantity'] as num?)?.toInt() ?? 1,
      freeQuantity: (m['free_quantity'] as num?)?.toInt() ?? 1,
      targets: t,
      bogoRules: r,
    );
  }
}

/// What the app actually applies right now
class _AppliedVoucher {
  final StoreVoucherDto voucher;
  final double discountAmount;

  /// b1t1 free items payload to be inserted as order_items (unit_price=0, line_subtotal=0)
  final List<Map<String, dynamic>> freeItemsPayload;

  const _AppliedVoucher({
    required this.voucher,
    required this.discountAmount,
    required this.freeItemsPayload,
  });
}

/// =======================================================
/// CART SCREEN
/// =======================================================
class CartScreen extends StatefulWidget {
  static const route = '/cart';
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  late CartArgs args;

  /// local editable cart keyed by menu+variant
  late Map<String, _CartLine> _cartByKey;

  bool _placingOrder = false;
  String? _placeError;

  // vouchers
  bool _loadingVouchers = false;
  String? _voucherLoadError;
  List<StoreVoucherDto> _vouchers = [];
  final Set<int> _usedVoucherIds = {};

  _AppliedVoucher? _applied; // selected + computed

  /// menu_id -> category_id (for category-target / bogo rules)
  final Map<int, int?> _menuCategoryById = {};
  int? _activeCartIdCache;
  Future<void> _cartSyncChain = Future<void>.value();
  bool _addonOptionsLoaded = false;
  List<StoreMenuItemDto> _addonOptions = const <StoreMenuItemDto>[];
  bool _initializedFromArgs = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromArgs) return;

    final a = ModalRoute.of(context)!.settings.arguments;
    if (a is! CartArgs) {
      throw Exception(
        'CartScreen requires arguments of type CartArgs. '
        'Use Navigator.pushNamed(context, CartScreen.route, arguments: CartArgs(...))',
      );
    }

    args = a;
    _cartByKey = <String, _CartLine>{};
    if (args.selectedItems.isNotEmpty) {
      for (final s in args.selectedItems) {
        if (s.qty <= 0) continue;
        final menu =
            _findMenu(s.menuId) ??
            StoreMenuItemDto(
              menuId: s.menuId,
              name: s.name,
              price: s.unitPrice,
              imageUrl: s.imageUrl,
            );
        final key = _lineKey(s.menuId, s.variantId, s.addons);
        _cartByKey[key] = _CartLine(
          key: key,
          item: menu,
          qty: s.qty,
          unitPrice: s.unitPrice,
          variantId: s.variantId,
          sizeLabel: s.sizeLabel,
          addons: s.addons,
          cartItemId: null,
        );
      }
    } else {
      args.cart.forEach((menuId, qty) {
        final menu = _findMenu(menuId);
        if (menu == null || qty <= 0) return;
        final key = _lineKey(menuId, null, const []);
        _cartByKey[key] = _CartLine(
          key: key,
          item: menu,
          qty: qty,
          unitPrice: menu.price.toDouble(),
          variantId: null,
          sizeLabel: null,
          addons: const [],
          cartItemId: null,
        );
      });
    }
    _initializedFromArgs = true;

    // Load voucher data + category map once
    _bootstrap();
  }

  bool _bootstrapped = false;
  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    if (args.selectedItems.isEmpty) {
      await _loadCartFromDbWithAddons();
    }
    await _loadMenuCategoriesForCart();
    await _loadAvailableVouchers();
  }

  Future<void> _loadCartFromDbWithAddons() async {
    try {
      final cartId = await _getOrCreateActiveCartId();
      if (cartId == null) return;

      final itemRows = await _client
          .from('cart_items')
          .select('cart_item_id, menu_id, variant_id, quantity, price')
          .eq('cart_id', cartId);

      if ((itemRows as List).isEmpty) return;
      final rawItems = itemRows.cast<Map<String, dynamic>>();
      final cartItemQtyById = <int, int>{
        for (final raw in rawItems)
          (raw['cart_item_id'] as num).toInt():
              (raw['quantity'] as num?)?.toInt() ?? 0,
      };

      final cartItemIds = rawItems
          .map((e) => (e['cart_item_id'] as num).toInt())
          .toList(growable: false);

      final addonRows = cartItemIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : ((await _client
                        .from('cart_item_addons')
                        .select(
                          'cart_item_id, addon_menu_id, quantity, unit_price',
                        )
                        .inFilter('cart_item_id', cartItemIds))
                    as List)
                .cast<Map<String, dynamic>>();

      final menuIds = rawItems
          .map((e) => (e['menu_id'] as num).toInt())
          .toSet()
          .toList();
      final addonMenuIds = addonRows
          .map((e) => (e['addon_menu_id'] as num).toInt())
          .toSet()
          .toList();
      final allMenuIds = {...menuIds, ...addonMenuIds}.toList();

      final menuRows = allMenuIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : ((await _client
                        .from('store_menu_items')
                        .select('menu_id, name, price, image_url')
                        .inFilter('menu_id', allMenuIds))
                    as List)
                .cast<Map<String, dynamic>>();

      final menuById = <int, StoreMenuItemDto>{};
      for (final raw in menuRows) {
        final m = raw.cast<String, dynamic>();
        final id = (m['menu_id'] as num).toInt();
        menuById[id] = StoreMenuItemDto(
          menuId: id,
          name: (m['name'] ?? 'Item').toString(),
          price: (m['price'] as num?) ?? 0,
          imageUrl: m['image_url']?.toString(),
        );
      }

      final variantIds = rawItems
          .map((e) => (e['variant_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();
      final variantLabelById = <int, String>{};
      if (variantIds.isNotEmpty) {
        final variantRows = await _client
            .from('store_menu_item_variants')
            .select('variant_id, size_label')
            .inFilter('variant_id', variantIds);
        for (final raw in (variantRows as List)) {
          final v = (raw as Map).cast<String, dynamic>();
          variantLabelById[(v['variant_id'] as num).toInt()] =
              (v['size_label'] ?? '').toString();
        }
      }

      final addonsByCartItemId = <int, List<CartAddonDto>>{};
      for (final raw in addonRows) {
        final m = raw.cast<String, dynamic>();
        final cartItemId = (m['cart_item_id'] as num).toInt();
        final addonMenuId = (m['addon_menu_id'] as num).toInt();
        final addonMenu = menuById[addonMenuId];
        final rawQty = (m['quantity'] as num?)?.toInt() ?? 0;
        final cartItemQty = cartItemQtyById[cartItemId] ?? 0;
        final normalizedQty = _normalizeAddonQtyFromDb(
          storedQty: rawQty,
          cartItemQty: cartItemQty,
        );
        addonsByCartItemId.putIfAbsent(cartItemId, () => []);
        addonsByCartItemId[cartItemId]!.add(
          CartAddonDto(
            menuId: addonMenuId,
            name: addonMenu?.name ?? 'Addon',
            unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
            qty: normalizedQty,
          ),
        );
      }

      final next = <String, _CartLine>{};
      for (final raw in rawItems) {
        final m = raw.cast<String, dynamic>();
        final cartItemId = (m['cart_item_id'] as num).toInt();
        final menuId = (m['menu_id'] as num).toInt();
        final menu = menuById[menuId] ?? _findMenu(menuId);
        if (menu == null) continue;
        final variantId = (m['variant_id'] as num?)?.toInt();
        final qty = (m['quantity'] as num?)?.toInt() ?? 0;
        if (qty <= 0) continue;
        final unitPrice =
            (m['price'] as num?)?.toDouble() ?? menu.price.toDouble();
        final sizeLabel = variantId == null
            ? null
            : variantLabelById[variantId];
        final addons = addonsByCartItemId[cartItemId] ?? const <CartAddonDto>[];
        final key = _lineKey(menuId, variantId, addons);
        next[key] = _CartLine(
          key: key,
          item: menu,
          qty: qty,
          unitPrice: unitPrice,
          variantId: variantId,
          sizeLabel: sizeLabel,
          addons: addons,
          cartItemId: cartItemId,
        );
      }

      if (!mounted) return;
      setState(() {
        _cartByKey = next;
      });
    } catch (_) {
      // fail silently; cart will remain as originally passed in
    }
  }

  StoreMenuItemDto? _findMenu(int menuId) {
    for (final m in args.menu) {
      if (m.menuId == menuId) return m;
    }
    return null;
  }

  String _lineKey(int menuId, int? variantId, List<CartAddonDto> addons) {
    final addonKey = _addonsKey(addons);
    return '$menuId:${variantId ?? 0}:$addonKey';
  }

  String _addonsKey(List<CartAddonDto> addons) {
    if (addons.isEmpty) return 'none';
    final sorted = [...addons]..sort((a, b) => a.menuId.compareTo(b.menuId));
    return sorted.map((a) => '${a.menuId}x${a.qty}').join('_');
  }

  int _normalizeAddonQtyFromDb({
    required int storedQty,
    required int cartItemQty,
  }) {
    if (storedQty <= 0) return 0;
    if (cartItemQty > 0 && storedQty % cartItemQty == 0) {
      final perUnitQty = storedQty ~/ cartItemQty;
      if (perUnitQty > 0) return perUnitQty;
    }
    return storedQty;
  }

  bool _isAddonCategoryName(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    return normalized == 'addon' || normalized == 'addons';
  }

  Future<void> _ensureAddonOptionsLoaded() async {
    if (_addonOptionsLoaded) return;
    _addonOptionsLoaded = true;

    try {
      final rows = await _client
          .from('store_menu_items')
          .select('''
            menu_id, name, price, image_url, category_id, is_available,
            store_categories(name)
          ''')
          .eq('store_id', args.storeId)
          .eq('is_available', true)
          .limit(500);

      final list = <StoreMenuItemDto>[];
      for (final raw in (rows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        final menuId = (m['menu_id'] as num?)?.toInt();
        if (menuId == null) continue;
        final category = (m['store_categories'] as Map?)?.cast<String, dynamic>();
        final categoryName = (category?['name'] ?? '').toString();
        if (!_isAddonCategoryName(categoryName)) continue;

        list.add(
          StoreMenuItemDto(
            menuId: menuId,
            name: (m['name'] ?? 'Addon').toString(),
            price: (m['price'] as num?) ?? 0,
            imageUrl: m['image_url']?.toString(),
          ),
        );
        _menuCategoryById[menuId] = (m['category_id'] as num?)?.toInt();
      }

      list.sort((a, b) => a.name.compareTo(b.name));
      _addonOptions = list;
    } catch (_) {
      _addonOptions = const <StoreMenuItemDto>[];
      _addonOptionsLoaded = false;
    }
  }

  List<CartAddonDto> _normalizeAddons(List<CartAddonDto> addons) {
    final byMenuId = <int, CartAddonDto>{};
    for (final addon in addons) {
      if (addon.qty <= 0) continue;
      final existing = byMenuId[addon.menuId];
      if (existing == null) {
        byMenuId[addon.menuId] = addon;
      } else {
        byMenuId[addon.menuId] = CartAddonDto(
          menuId: addon.menuId,
          name: addon.name,
          unitPrice: addon.unitPrice,
          qty: existing.qty + addon.qty,
        );
      }
    }
    final list = byMenuId.values.toList();
    list.sort((a, b) => a.menuId.compareTo(b.menuId));
    return list;
  }

  Future<List<_VariantEditorOption>> _loadVariantOptionsForLine(
    _CartLine line,
  ) async {
    try {
      final rows = await _client
          .from('store_menu_item_variants')
          .select()
          .eq('menu_id', line.item.menuId)
          .order('sort_order', ascending: true);

      final options = <_VariantEditorOption>[];
      for (final raw in (rows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        final variantId = (m['variant_id'] as num?)?.toInt();
        if (variantId == null) continue;
        final isActive = (m['is_active'] as bool?) ?? true;
        final isAvailable = (m['is_available'] as bool?) ?? true;
        if (!isActive || !isAvailable) continue;

        final label =
            (m['size_label'] ??
                    m['variant_name'] ??
                    m['name'] ??
                    m['size'] ??
                    'Variant')
                .toString();
        final price =
            (m['price'] as num?)?.toDouble() ??
            (m['amount'] as num?)?.toDouble() ??
            line.unitPrice;
        options.add(
          _VariantEditorOption(
            variantId: variantId,
            label: label,
            unitPrice: price,
          ),
        );
      }

      if (options.isEmpty) return const <_VariantEditorOption>[];

      if (line.variantId != null &&
          !options.any((o) => o.variantId == line.variantId)) {
        options.insert(
          0,
          _VariantEditorOption(
            variantId: line.variantId,
            label: (line.sizeLabel ?? 'Variant').toString(),
            unitPrice: line.unitPrice,
          ),
        );
      }

      return options;
    } catch (_) {
      return const <_VariantEditorOption>[];
    }
  }

  Future<_LineEditorResult?> _openLineEditor(_CartLine line) async {
    await _ensureAddonOptionsLoaded();
    if (!mounted) return null;
    final variantOptions = await _loadVariantOptionsForLine(line);
    if (!mounted) return null;

    int? selectedVariantId = line.variantId;
    String? selectedSizeLabel = line.sizeLabel;
    double selectedUnitPrice = line.unitPrice;
    int selectedQty = line.qty;
    if (variantOptions.isNotEmpty) {
      final current = variantOptions.firstWhere(
        (v) => v.variantId == line.variantId,
        orElse: () => variantOptions.first,
      );
      selectedVariantId = current.variantId;
      selectedSizeLabel = current.label;
      selectedUnitPrice = current.unitPrice;
    }

    final optionByMenuId = <int, _AddonEditorOption>{
      for (final option in _addonOptions)
        option.menuId: _AddonEditorOption(
          menuId: option.menuId,
          name: option.name,
          unitPrice: option.price.toDouble(),
        ),
    };

    for (final addon in line.addons) {
      optionByMenuId.putIfAbsent(
        addon.menuId,
        () => _AddonEditorOption(
          menuId: addon.menuId,
          name: addon.name,
          unitPrice: addon.unitPrice,
        ),
      );
    }

    final options = optionByMenuId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final initialCounts = <int, int>{
      for (final addon in line.addons)
        if (addon.qty > 0) addon.menuId: addon.qty,
    };

    return showModalBottomSheet<_LineEditorResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final counts = Map<int, int>.from(initialCounts);
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double addonsTotalPerItem() {
              double sum = 0;
              for (final option in options) {
                final qty = counts[option.menuId] ?? 0;
                if (qty <= 0) continue;
                sum += option.unitPrice * qty;
              }
              return sum;
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${selectedSizeLabel == null ? 'Regular' : selectedSizeLabel} • Qty $selectedQty',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Base price: ₱${selectedUnitPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Qty',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              _QtyBtn(
                                icon: Icons.remove_rounded,
                                onTap: selectedQty <= 1
                                    ? null
                                    : () {
                                        setSheetState(() {
                                          selectedQty =
                                              (selectedQty - 1).clamp(1, 99);
                                        });
                                      },
                                disabled: selectedQty <= 1,
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '$selectedQty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _QtyBtn(
                                icon: Icons.add_rounded,
                                onTap: () {
                                  setSheetState(() {
                                    selectedQty = (selectedQty + 1).clamp(1, 99);
                                  });
                                },
                                disabled: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (variantOptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Edit Size',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: variantOptions.map((variant) {
                          final selected =
                              selectedVariantId == variant.variantId;
                          return ChoiceChip(
                            label: Text(
                              '${variant.label} • ₱${variant.unitPrice.toStringAsFixed(2)}',
                            ),
                            selected: selected,
                            onSelected: (_) {
                              setSheetState(() {
                                selectedVariantId = variant.variantId;
                                selectedSizeLabel = variant.label;
                                selectedUnitPrice = variant.unitPrice;
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Edit Add-ons',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'No add-ons available for this item.',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 300,
                        child: ListView.separated(
                          itemCount: options.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final option = options[i];
                            final qty = counts[option.menuId] ?? 0;
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          option.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₱${option.unitPrice.toStringAsFixed(2)} each',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _QtyBtn(
                                        icon: Icons.remove_rounded,
                                        onTap: qty <= 0
                                            ? null
                                            : () {
                                                setSheetState(() {
                                                  counts[option.menuId] =
                                                      (qty - 1).clamp(0, 99);
                                                });
                                              },
                                        disabled: qty <= 0,
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 22,
                                        child: Text(
                                          '$qty',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _QtyBtn(
                                        icon: Icons.add_rounded,
                                        onTap: () {
                                          setSheetState(() {
                                            counts[option.menuId] =
                                                (qty + 1).clamp(0, 99);
                                          });
                                        },
                                        disabled: false,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add-ons total per item',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '₱${addonsTotalPerItem().toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final selected = options
                                  .map((option) {
                                    final qty = counts[option.menuId] ?? 0;
                                    if (qty <= 0) return null;
                                    return CartAddonDto(
                                      menuId: option.menuId,
                                      name: option.name,
                                      unitPrice: option.unitPrice,
                                      qty: qty,
                                    );
                                  })
                                  .whereType<CartAddonDto>()
                                  .toList(growable: false);
                              Navigator.pop(
                                ctx,
                                _LineEditorResult(
                                  qty: selectedQty,
                                  variantId: selectedVariantId,
                                  sizeLabel: selectedSizeLabel,
                                  unitPrice: selectedUnitPrice,
                                  addons: _normalizeAddons(selected),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                            ),
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editLineDetails(String lineKey) async {
    final line = _cartByKey[lineKey];
    if (line == null) return;

    final edited = await _openLineEditor(line);
    if (edited == null) return;

    final normalizedAddons = _normalizeAddons(edited.addons);
    final newKey = _lineKey(line.item.menuId, edited.variantId, normalizedAddons);
    final targetLine = _cartByKey[newKey];
    final willMerge = targetLine != null && targetLine.key != line.key;

    late _CartLine lineToSync;
    _CartLine? lineToDelete;

    if (willMerge) {
      lineToDelete = line;
      lineToSync = targetLine.copyWith(
        key: newKey,
        qty: targetLine.qty + edited.qty,
        unitPrice: edited.unitPrice,
        variantId: edited.variantId,
        sizeLabel: edited.sizeLabel,
        addons: normalizedAddons,
      );
    } else {
      lineToSync = line.copyWith(
        key: newKey,
        qty: edited.qty,
        unitPrice: edited.unitPrice,
        variantId: edited.variantId,
        sizeLabel: edited.sizeLabel,
        addons: normalizedAddons,
      );
    }

    setState(() {
      _cartByKey.remove(lineKey);
      _cartByKey[lineToSync.key] = lineToSync;
      _placeError = null;
    });
    _recomputeAppliedVoucherIfAny();

    await _loadMenuCategoriesForCart();

    try {
      final deleteLine = lineToDelete;
      await _queueCartSync(() async {
        if (deleteLine != null &&
            deleteLine.cartItemId != null &&
            deleteLine.cartItemId != lineToSync.cartItemId) {
          await _syncLineToDb(deleteLine.copyWith(qty: 0));
        }
        await _syncLineToDb(lineToSync);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _placeError = 'Failed to sync cart update: $e');
    }
  }

  Map<int, int> get _menuQtyById {
    final map = <int, int>{};
    for (final line in _cartByKey.values) {
      if (line.qty <= 0) continue;
      map[line.item.menuId] = (map[line.item.menuId] ?? 0) + line.qty;
      for (final addon in line.addons) {
        final addonQty = addon.qty * line.qty;
        if (addonQty <= 0) continue;
        map[addon.menuId] = (map[addon.menuId] ?? 0) + addonQty;
      }
    }
    return map;
  }

  List<_CartLine> get _lines {
    final list = _cartByKey.values.where((e) => e.qty > 0).toList();
    list.sort((a, b) => a.item.name.compareTo(b.item.name));
    return list;
  }

  double get _baseSubtotal {
    double sum = 0;
    for (final line in _lines) {
      sum += line.unitPrice * line.qty;
    }
    return sum;
  }

  double get _addonsTotal {
    double sum = 0;
    for (final line in _lines) {
      sum += line.addonsUnitTotal * line.qty;
    }
    return sum;
  }

  double get _subtotal => _baseSubtotal + _addonsTotal;

  double get _discount => _applied?.discountAmount ?? 0.0;

  double get _total => (_subtotal - _discount).clamp(0.0, double.infinity);

  int get _itemCount => _lines.fold(0, (a, b) => a + b.qty);

  Future<int?> _getOrCreateActiveCartId() async {
    if (_activeCartIdCache != null) return _activeCartIdCache;
    final userId = await _resolveUserId(role: 'customer');

    final rows = await _client
        .from('carts')
        .select('cart_id')
        .eq('user_id', userId)
        .eq('store_id', args.storeId)
        .eq('status', 'active')
        .limit(1);

    if ((rows as List).isNotEmpty) {
      _activeCartIdCache = ((rows.first as Map)['cart_id'] as num).toInt();
      return _activeCartIdCache;
    }

    final created = await _client
        .from('carts')
        .insert({
          'user_id': userId,
          'store_id': args.storeId,
          'status': 'active',
        })
        .select('cart_id')
        .single();
    _activeCartIdCache = (created['cart_id'] as num).toInt();
    return _activeCartIdCache;
  }

  Future<void> _syncLineToDb(_CartLine line) async {
    final cartId = await _getOrCreateActiveCartId();
    if (cartId == null) return;

    final existingCartItemId = await _findExistingCartItemId(
      cartId: cartId,
      line: line,
    );

    if (line.qty <= 0) {
      if (existingCartItemId != null) {
        await _client
            .from('cart_items')
            .delete()
            .eq('cart_item_id', existingCartItemId);
        await _touchCartUpdatedAt(cartId);
      }
      return;
    }

    int cartItemId;
    if (existingCartItemId == null) {
      final created = await _client
          .from('cart_items')
          .insert({
        'cart_id': cartId,
        'store_id': args.storeId,
        'menu_id': line.item.menuId,
        'variant_id': line.variantId,
        'quantity': line.qty,
        'price': line.unitPrice,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
          .select('cart_item_id')
          .single();
      cartItemId = (created['cart_item_id'] as num).toInt();
    } else {
      cartItemId = existingCartItemId;
      await _client
          .from('cart_items')
          .update({
            'quantity': line.qty,
            'variant_id': line.variantId,
            'price': line.unitPrice,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('cart_item_id', cartItemId);
    }

    await _syncLineAddonsToDb(cartItemId: cartItemId, line: line);

    final localLine = _cartByKey[line.key];
    if (localLine != null && localLine.cartItemId != cartItemId) {
      _cartByKey[line.key] = localLine.copyWith(cartItemId: cartItemId);
    }

    await _client
        .from('carts')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('cart_id', cartId);
  }

  Future<int?> _findExistingCartItemId({
    required int cartId,
    required _CartLine line,
  }) async {
    if (line.cartItemId != null) {
      final byId = await _client
          .from('cart_items')
          .select('cart_item_id')
          .eq('cart_id', cartId)
          .eq('cart_item_id', line.cartItemId!)
          .maybeSingle();
      if (byId != null) {
        return (byId['cart_item_id'] as num).toInt();
      }
    }

    final q = _client
        .from('cart_items')
        .select('cart_item_id, quantity')
        .eq('cart_id', cartId)
        .eq('menu_id', line.item.menuId);
    final rows = line.variantId == null
        ? await q.isFilter('variant_id', null)
        : await q.eq('variant_id', line.variantId!);

    final candidates = (rows as List).cast<Map<String, dynamic>>();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) {
      return (candidates.first['cart_item_id'] as num).toInt();
    }

    final cartItemQtyById = <int, int>{
      for (final raw in candidates)
        (raw['cart_item_id'] as num).toInt():
            (raw['quantity'] as num?)?.toInt() ?? 0,
    };
    final cartItemIds = cartItemQtyById.keys.toList(growable: false);
    final addonRows = cartItemIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : ((await _client
                      .from('cart_item_addons')
                      .select('cart_item_id, addon_menu_id, quantity')
                      .inFilter('cart_item_id', cartItemIds))
                  as List)
              .cast<Map<String, dynamic>>();
    final addonKeyByCartItemId = _buildAddonKeyByCartItemId(
      addonRows: addonRows,
      cartItemQtyById: cartItemQtyById,
    );
    final targetAddonKey = _addonsKey(line.addons);
    for (final raw in candidates) {
      final cartItemId = (raw['cart_item_id'] as num).toInt();
      if ((addonKeyByCartItemId[cartItemId] ?? 'none') == targetAddonKey) {
        return cartItemId;
      }
    }

    return (candidates.first['cart_item_id'] as num).toInt();
  }

  Map<int, String> _buildAddonKeyByCartItemId({
    required List<Map<String, dynamic>> addonRows,
    required Map<int, int> cartItemQtyById,
  }) {
    final partsByCartItemId = <int, List<String>>{};
    for (final raw in addonRows) {
      final m = raw.cast<String, dynamic>();
      final cartItemId = (m['cart_item_id'] as num).toInt();
      final addonMenuId = (m['addon_menu_id'] as num).toInt();
      final rawQty = (m['quantity'] as num?)?.toInt() ?? 0;
      final cartItemQty = cartItemQtyById[cartItemId] ?? 0;
      final normalizedQty = _normalizeAddonQtyFromDb(
        storedQty: rawQty,
        cartItemQty: cartItemQty,
      );
      if (normalizedQty <= 0) continue;
      partsByCartItemId.putIfAbsent(cartItemId, () => []);
      partsByCartItemId[cartItemId]!.add('${addonMenuId}x$normalizedQty');
    }

    final keys = <int, String>{};
    for (final cartItemId in cartItemQtyById.keys) {
      final parts = [...(partsByCartItemId[cartItemId] ?? const <String>[])];
      parts.sort();
      keys[cartItemId] = parts.isEmpty ? 'none' : parts.join('_');
    }
    return keys;
  }

  Future<void> _syncLineAddonsToDb({
    required int cartItemId,
    required _CartLine line,
  }) async {
    if (line.addons.isEmpty) {
      await _client
          .from('cart_item_addons')
          .delete()
          .eq('cart_item_id', cartItemId);
      return;
    }

    final addonIds = line.addons.map((a) => a.menuId).toList(growable: false);
    await _client
        .from('cart_item_addons')
        .delete()
        .eq('cart_item_id', cartItemId)
        .not('addon_menu_id', 'in', '(${addonIds.join(',')})');

    final payload = line.addons
        .where((a) => a.qty > 0)
        .map((a) {
          final totalQty = a.qty * line.qty;
          return <String, dynamic>{
            'cart_item_id': cartItemId,
            'addon_menu_id': a.menuId,
            'quantity': totalQty,
            'unit_price': a.unitPrice,
            'line_subtotal': a.unitPrice * totalQty,
          };
        })
        .toList();

    if (payload.isEmpty) {
      await _client
          .from('cart_item_addons')
          .delete()
          .eq('cart_item_id', cartItemId);
      return;
    }

    await _client
        .from('cart_item_addons')
        .upsert(payload, onConflict: 'cart_item_id,addon_menu_id');
  }

  Future<void> _touchCartUpdatedAt(int cartId) async {
    await _client
        .from('carts')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('cart_id', cartId);
  }

  Future<void> _add(String lineKey) async {
    final line = _cartByKey[lineKey];
    if (line == null) return;
    final updated = line.copyWith(qty: line.qty + 1);
    setState(() => _cartByKey[lineKey] = updated);
    _recomputeAppliedVoucherIfAny();
    try {
      await _queueCartSync(() => _syncLineToDb(updated));
    } catch (e) {
      if (!mounted) return;
      setState(() => _placeError = 'Failed to sync cart update: $e');
    }
  }

  Future<void> _remove(String lineKey) async {
    final line = _cartByKey[lineKey];
    if (line == null) return;
    _CartLine updated;
    if (line.qty <= 1) {
      setState(() => _cartByKey.remove(lineKey));
      updated = line.copyWith(qty: 0);
      _recomputeAppliedVoucherIfAny();
    } else {
      updated = line.copyWith(qty: line.qty - 1);
      setState(() => _cartByKey[lineKey] = updated);
      _recomputeAppliedVoucherIfAny();
    }
    try {
      await _queueCartSync(() => _syncLineToDb(updated));
    } catch (e) {
      if (!mounted) return;
      setState(() => _placeError = 'Failed to sync cart update: $e');
    }
  }

  Future<void> _queueCartSync(Future<void> Function() task) {
    final next = _cartSyncChain.then((_) => task());
    _cartSyncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _clearCart() async {
    setState(() {
      _cartByKey.clear();
      _applied = null;
    });

    try {
      final cartId = await _getOrCreateActiveCartId();
      if (cartId != null) {
        await _client.from('cart_items').delete().eq('cart_id', cartId);
      }
    } catch (_) {}
  }

  void _clearVoucher() {
    setState(() => _applied = null);
  }

  Future<void> _clearActiveCartAfterOrder({
    required int userId,
    required int storeId,
  }) async {
    final rows = await _client
        .from('carts')
        .select('cart_id')
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .eq('status', 'active')
        .limit(1);

    if ((rows as List).isEmpty) return;
    final cartId = ((rows.first as Map)['cart_id'] as num).toInt();

    await _client.from('cart_items').delete().eq('cart_id', cartId);
    await _client
        .from('carts')
        .update({'status': 'checked_out'})
        .eq('cart_id', cartId);
  }

  Future<void> _loadMenuCategoriesForCart() async {
    try {
      final ids = _menuQtyById.keys.toList();
      if (ids.isEmpty) return;

      final rows = await _client
          .from('store_menu_items')
          .select('menu_id, category_id')
          .inFilter('menu_id', ids);

      for (final r in (rows as List)) {
        final m = (r as Map).cast<String, dynamic>();
        _menuCategoryById[(m['menu_id'] as num).toInt()] =
            (m['category_id'] as num?)?.toInt();
      }
    } catch (_) {
      // If this fails, category-based vouchers just won't be "applicable".
    }
  }

  Future<void> _loadAvailableVouchers() async {
    setState(() {
      _loadingVouchers = true;
      _voucherLoadError = null;
    });

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final rows = await _client
          .from('store_vouchers')
          .select('''
            voucher_id, store_id, code, title, details, voucher_type,
            discount_type, discount_value, min_spend, max_discount,
            buy_menu_id, free_menu_id, buy_quantity, free_quantity,
            starts_at, ends_at, usage_limit, usage_limit_per_user,
            is_active,
            store_voucher_targets(target_type, category_id, menu_id),
            store_voucher_bogo_rules(rule_id, buy_type, buy_menu_id, buy_category_id, buy_qty,
                                     get_type, get_menu_id, get_category_id, get_qty, get_discount_percent)
          ''')
          .eq('store_id', args.storeId)
          .eq('is_active', true)
          .or('starts_at.lte.$nowIso,starts_at.is.null')
          .or('ends_at.gte.$nowIso,ends_at.is.null')
          .order('created_at', ascending: false)
          .limit(200);

      final list = (rows as List)
          .map(
            (e) => StoreVoucherDto.fromMap((e as Map).cast<String, dynamic>()),
          )
          .toList();

      final usedIds = await _fetchUsedVoucherIds(list);

      final shouldClearApplied =
          _applied != null && usedIds.contains(_applied!.voucher.voucherId);

      setState(() {
        _usedVoucherIds
          ..clear()
          ..addAll(usedIds);
        if (shouldClearApplied) {
          _applied = null;
        }
        _vouchers = list;
        _loadingVouchers = false;
      });
    } catch (e) {
      setState(() {
        _voucherLoadError = e.toString();
        _loadingVouchers = false;
      });
    }
  }

  Future<Set<int>> _fetchUsedVoucherIds(List<StoreVoucherDto> vouchers) async {
    try {
      if (vouchers.isEmpty) return {};
      final userId = await _resolveUserId(role: 'customer');
      final voucherIds = vouchers.map((v) => v.voucherId).toSet().toList();
      if (voucherIds.isEmpty) return {};

      final rows = await _client
          .from('orders')
          .select('voucher_id')
          .eq('user_id', userId)
          .inFilter('status', ['completed', 'reviewed', 'paid', 'preparing'])
          .inFilter('voucher_id', voucherIds);

      final used = <int>{};
      for (final raw in (rows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        final id = (m['voucher_id'] as num?)?.toInt();
        if (id != null) used.add(id);
      }
      return used;
    } catch (_) {
      return {};
    }
  }

  /// =======================================================
  /// Resolve bigint users.user_id using Supabase Auth user UUID
  /// =======================================================
  Future<int> _resolveUserId({String role = 'customer'}) async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw Exception('You must be logged in to place an order.');
    }

    final rows = await _client
        .from('users')
        .select('user_id')
        .eq('auth_user_id', authUser.id)
        .eq('role', role)
        .limit(1);

    if ((rows as List).isEmpty) {
      throw Exception(
        'No "$role" profile found for this account.\n'
        'Create a users row with role="$role" linked to auth_user_id.',
      );
    }

    final row = (rows as List).first as Map;
    return (row['user_id'] as num).toInt();
  }

  String _generateReference() {
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final rand = Random().nextInt(9000) + 1000;
    return 'SIPLY-$stamp-$rand';
  }

  /// =======================================================
  /// Voucher applicability + computation
  /// =======================================================
  bool _voucherIsApplicable(StoreVoucherDto v) {
    // empty cart => nothing applicable
    if (_lines.isEmpty) return false;

    // min spend check (most systems use subtotal; you can switch to eligibleSubtotal if you want)
    if (_subtotal < v.minSpend) return false;

    switch (v.voucherType) {
      case 'discount':
        // must have a discountType/value
        if ((v.discountType ?? '').isEmpty) return false;
        if ((v.discountValue ?? 0) <= 0) return false;

        // must have at least one eligible item based on targets
        return _eligibleUnitTotalForDiscountVoucher(v) > 0;

      case 'b1t1':
        if (v.buyMenuId == null || v.freeMenuId == null) return false;
        final buyQty = _menuQtyById[v.buyMenuId!] ?? 0;
        return buyQty >= v.buyQuantity;

      case 'bogo':
        // must have rules and meet at least one rule
        if (v.bogoRules.isEmpty) return false;
        for (final rule in v.bogoRules) {
          if (_bogoRuleTimes(rule) > 0 && _getQtyAvailableForRule(rule) > 0) {
            return true;
          }
        }
        return false;

      default:
        return false;
    }
  }

  bool _isLineEligibleForVoucher(StoreVoucherDto v, _CartLine line) {
    final menuId = line.item.menuId;
    final catId = _menuCategoryById[menuId];

    switch (v.voucherType) {
      case 'discount':
        if (v.targets.isEmpty) return true;
        if (v.targets.any((t) => t.targetType == 'all_items')) return true;
        for (final t in v.targets) {
          if (t.targetType == 'menu_item' && t.menuId == menuId) return true;
          if (t.targetType == 'category' && t.categoryId == catId) return true;
        }
        return false;

      case 'b1t1':
        return menuId == v.buyMenuId || menuId == v.freeMenuId;

      case 'bogo':
        for (final rule in v.bogoRules) {
          if (rule.buyType == 'menu_item' && rule.buyMenuId == menuId) {
            return true;
          }
          if (rule.buyType == 'category' && rule.buyCategoryId == catId) {
            return true;
          }
          if (rule.getType == 'menu_item' && rule.getMenuId == menuId) {
            return true;
          }
          if (rule.getType == 'category' && rule.getCategoryId == catId) {
            return true;
          }
        }
        return false;
      default:
        return false;
    }
  }

  String? _voucherLabelForLine(_CartLine line) {
    final applied = _applied;
    if (applied == null) return null;
    if (!_isLineEligibleForVoucher(applied.voucher, line)) return null;

    if (applied.voucher.voucherType == 'b1t1') {
      final freeItem = _findMenu(applied.voucher.freeMenuId ?? -1);
      if (freeItem != null) {
        return 'Voucher applied: Free ${freeItem.name}';
      }
    }
    if (applied.voucher.voucherType == 'discount') {
      final key = _discountVoucherLineKey(applied.voucher);
      if (key != line.key) return null;
    }
    return 'Voucher applied: ${applied.voucher.code}';
  }

  String? _voucherSubtitleForCard(StoreVoucherDto v) {
    if (v.voucherType == 'b1t1') {
      final freeItem = _findMenu(v.freeMenuId ?? -1);
      if (freeItem != null) {
        return 'Free item: ${freeItem.name}';
      }
    }
    final details = (v.details ?? '').trim();
    return details.isEmpty ? null : details;
  }

  String _voucherSummaryLine(_AppliedVoucher applied) {
    if (applied.voucher.voucherType == 'b1t1') {
      final freeItem = _findMenu(applied.voucher.freeMenuId ?? -1);
      if (freeItem != null) {
        return 'Free: ${freeItem.name} • -₱${applied.discountAmount.toStringAsFixed(2)}';
      }
    }
    return '${applied.voucher.code} • -₱${applied.discountAmount.toStringAsFixed(2)}';
  }

  String? _discountVoucherLineKey(StoreVoucherDto v) {
    if (v.voucherType != 'discount') return null;
    if (_lines.isEmpty) return null;

    final eligible =
        _lines.where((line) => _isLineEligibleForVoucher(v, line)).toList();
    if (eligible.isEmpty) return null;

    eligible.sort((a, b) => b.unitTotal.compareTo(a.unitTotal));
    return eligible.first.key;
  }

  double _eligibleUnitTotalForDiscountVoucher(StoreVoucherDto v) {
    final targets = v.targets;

    // If no targets set, assume all_items
    if (targets.isEmpty) {
      if (_lines.isEmpty) return 0;
      final top = [..._lines]..sort((a, b) => b.unitTotal.compareTo(a.unitTotal));
      return top.first.unitTotal;
    }

    bool hasAllItems = targets.any((t) => t.targetType == 'all_items');
    if (hasAllItems) {
      if (_lines.isEmpty) return 0;
      final top = [..._lines]..sort((a, b) => b.unitTotal.compareTo(a.unitTotal));
      return top.first.unitTotal;
    }

    final allowedMenuIds = <int>{};
    final allowedCategoryIds = <int>{};

    for (final t in targets) {
      if (t.targetType == 'menu_item' && t.menuId != null) {
        allowedMenuIds.add(t.menuId!);
      }
      if (t.targetType == 'category' && t.categoryId != null) {
        allowedCategoryIds.add(t.categoryId!);
      }
    }

    double bestUnitTotal = 0;
    for (final line in _lines) {
      final menuId = line.item.menuId;
      final catId = _menuCategoryById[menuId];

      final okByMenu = allowedMenuIds.contains(menuId);
      final okByCat = catId != null && allowedCategoryIds.contains(catId);

      if (okByMenu || okByCat) {
        if (line.unitTotal > bestUnitTotal) {
          bestUnitTotal = line.unitTotal;
        }
      }
    }

    return bestUnitTotal;
  }

  int _quantityForCategoryInCart(int categoryId) {
    int qty = 0;
    for (final entry in _menuQtyById.entries) {
      final menuId = entry.key;
      if (_menuCategoryById[menuId] == categoryId) {
        qty += entry.value;
      }
    }
    return qty;
  }

  int _buyQtyInCartForRule(BogoRuleDto rule) {
    if (rule.buyType == 'menu_item') {
      if (rule.buyMenuId == null) return 0;
      return _menuQtyById[rule.buyMenuId!] ?? 0;
    }

    if (rule.buyType == 'category') {
      if (rule.buyCategoryId == null) return 0;
      return _quantityForCategoryInCart(rule.buyCategoryId!);
    }

    return 0;
  }

  double _weightedAverageUnitPriceForCategory(int categoryId) {
    double sum = 0.0;
    int qty = 0;

    for (final line in _lines) {
      final baseCat = _menuCategoryById[line.item.menuId];
      if (baseCat == categoryId) {
        sum += line.unitPrice * line.qty;
        qty += line.qty;
      }

      for (final addon in line.addons) {
        final addonCat = _menuCategoryById[addon.menuId];
        final addonQty = addon.qty * line.qty;
        if (addonCat == categoryId && addonQty > 0) {
          sum += addon.unitPrice * addonQty;
          qty += addonQty;
        }
      }
    }

    if (qty <= 0) return 0.0;
    return sum / qty;
  }

  String _bogoTargetLabel({
    required String targetType,
    required int? menuId,
    required int? categoryId,
  }) {
    if (targetType == 'menu_item' && menuId != null) {
      return _findMenu(menuId)?.name ?? 'required item';
    }
    if (targetType == 'category' && categoryId != null) {
      return 'an item from the required category';
    }
    return 'an eligible item';
  }

  int _bogoRuleTimes(BogoRuleDto rule) {
    final buyQtyInCart = _buyQtyInCartForRule(rule);
    if (buyQtyInCart <= 0) return 0;
    return buyQtyInCart ~/ max(1, rule.buyQty);
  }

  int _getQtyAvailableForRule(BogoRuleDto rule) {
    int getQtyInCart = 0;

    if (rule.getType == 'menu_item') {
      if (rule.getMenuId == null) return 0;
      getQtyInCart = _menuQtyById[rule.getMenuId!] ?? 0;
    } else {
      if (rule.getCategoryId == null) return 0;
      getQtyInCart = _quantityForCategoryInCart(rule.getCategoryId!);
    }

    return getQtyInCart;
  }

  _AppliedVoucher _computeApplied(StoreVoucherDto v) {
    switch (v.voucherType) {
      case 'discount':
        final eligibleUnitTotal = _eligibleUnitTotalForDiscountVoucher(v);
        final type = (v.discountType ?? '').toString();
        final value = (v.discountValue ?? 0).toDouble();

        double discount = 0;
        if (type == 'percent') {
          discount = eligibleUnitTotal * (value / 100.0);
        } else {
          // fixed
          discount = value.clamp(0.0, eligibleUnitTotal);
        }

        if (v.maxDiscount != null && v.maxDiscount! > 0) {
          discount = discount.clamp(0.0, v.maxDiscount!);
        }

        discount = discount.clamp(0.0, _subtotal);

        return _AppliedVoucher(
          voucher: v,
          discountAmount: discount,
          freeItemsPayload: const [],
        );

      case 'b1t1':
        final buyId = v.buyMenuId!;
        final freeId = v.freeMenuId!;
        final buyQtyInCart = _menuQtyById[buyId] ?? 0;

        final times = buyQtyInCart ~/ max(1, v.buyQuantity);
        final freeQty = times * max(1, v.freeQuantity);

        final freeItem = _findMenu(freeId);
        final freeUnitPrice = freeItem?.price.toDouble() ?? 0.0;
        final discount = (freeQty * freeUnitPrice).clamp(0.0, _subtotal);

        // Free item rows (unit_price=0, line_subtotal=0)
        final freePayload = freeQty <= 0
            ? <Map<String, dynamic>>[]
            : [
                {
                  'menu_id': freeId,
                  'quantity': freeQty,
                  'unit_price': 0.0,
                  'line_subtotal': 0.0,
                  'is_free_item': true,
                  'applied_voucher_id': v.voucherId,
                },
              ];

        return _AppliedVoucher(
          voucher: v,
          discountAmount: discount,
          freeItemsPayload: freePayload,
        );

      case 'bogo':
        double discount = 0.0;

        for (final rule in v.bogoRules) {
          final times = _bogoRuleTimes(rule);
          if (times <= 0) continue;

          final getQtyAvailable = _getQtyAvailableForRule(rule);
          if (getQtyAvailable <= 0) continue;

          final eligibleGetQty = min(
            getQtyAvailable,
            times * max(1, rule.getQty),
          );

          // estimate unit price for get items:
          // - if menu_item => exact
          // - if category => take average of items in that category in cart (simple & reasonable preview)
          double unitPrice = 0.0;

          if (rule.getType == 'menu_item') {
            final it = _findMenu(rule.getMenuId!);
            unitPrice = it?.price.toDouble() ?? 0.0;
          } else {
            // category: use weighted average unit price across matching cart lines + addons
            if (rule.getCategoryId != null) {
              unitPrice = _weightedAverageUnitPriceForCategory(
                rule.getCategoryId!,
              );
            }
          }

          final pct = (rule.getDiscountPercent / 100.0).clamp(0.0, 1.0);
          discount += eligibleGetQty * unitPrice * pct;
        }

        discount = discount.clamp(0.0, _subtotal);

        return _AppliedVoucher(
          voucher: v,
          discountAmount: discount,
          freeItemsPayload: const [],
        );

      default:
        return _AppliedVoucher(
          voucher: v,
          discountAmount: 0.0,
          freeItemsPayload: const [],
        );
    }
  }

  void _recomputeAppliedVoucherIfAny() {
    final current = _applied;
    if (current == null) return;

    // if cart changed and voucher no longer applicable -> remove it
    if (!_voucherIsApplicable(current.voucher)) {
      setState(() => _applied = null);
      return;
    }

    // else recompute discount/free
    setState(() => _applied = _computeApplied(current.voucher));
  }

  Future<void> _openVoucherPicker() async {
    if (_loadingVouchers) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final applicable = _vouchers.where(_voucherIsApplicable).toList();
        final notApplicable = _vouchers
            .where((v) => !_voucherIsApplicable(v))
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select a Voucher',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearVoucher();
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ),

                if (_voucherLoadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _voucherLoadError!,
                      style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                if (_vouchers.isEmpty && _voucherLoadError == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No vouchers available right now.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),

                if (applicable.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Applicable',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: applicable.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = applicable[i];
                        final preview = _computeApplied(v);
                        final selected =
                            _applied?.voucher.voucherId == v.voucherId;

                        final isUsed = _usedVoucherIds.contains(v.voucherId);
                        return _VoucherCard(
                          voucher: v,
                          enabled: !isUsed,
                          selected: selected,
                          previewDiscount: preview.discountAmount,
                          subtitleOverride: _voucherSubtitleForCard(v),
                          isUsed: isUsed,
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() => _applied = preview);
                          },
                        );
                      },
                    ),
                  ),
                ],

                if (notApplicable.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Not applicable',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: notApplicable.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final v = notApplicable[i];
                        final isUsed = _usedVoucherIds.contains(v.voucherId);
                        return _VoucherCard(
                          voucher: v,
                          enabled: false,
                          selected: false,
                          previewDiscount: 0,
                          subtitleOverride: _whyNotApplicable(v),
                          isUsed: isUsed,
                          onTap: null,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _whyNotApplicable(StoreVoucherDto v) {
    if (_lines.isEmpty) return 'Your cart is empty.';
    if (_subtotal < v.minSpend) {
      return 'Minimum spend not reached (₱${v.minSpend.toStringAsFixed(2)}).';
    }

    if (v.voucherType == 'b1t1') {
      if (v.buyMenuId == null || v.freeMenuId == null) {
        return 'Incomplete voucher setup.';
      }
      final buyQty = _menuQtyById[v.buyMenuId!] ?? 0;
      return 'Need at least ${v.buyQuantity} of the required item (you have $buyQty).';
    }

    if (v.voucherType == 'discount') {
      final eligible = _eligibleUnitTotalForDiscountVoucher(v);
      if (eligible <= 0) return 'No eligible items in your cart.';
    }

    if (v.voucherType == 'bogo') {
      if (v.bogoRules.isEmpty) return 'Incomplete BOGO voucher setup.';

      for (final rule in v.bogoRules) {
        final requiredBuyQty = max(1, rule.buyQty);
        final buyQtyInCart = _buyQtyInCartForRule(rule);
        if (buyQtyInCart < requiredBuyQty) {
          final buyLabel = _bogoTargetLabel(
            targetType: rule.buyType,
            menuId: rule.buyMenuId,
            categoryId: rule.buyCategoryId,
          );
          return 'Need at least $requiredBuyQty of $buyLabel (you have $buyQtyInCart).';
        }

        final getQtyInCart = _getQtyAvailableForRule(rule);
        if (getQtyInCart <= 0) {
          final getLabel = _bogoTargetLabel(
            targetType: rule.getType,
            menuId: rule.getMenuId,
            categoryId: rule.getCategoryId,
          );
          return 'Add $getLabel to claim this BOGO voucher.';
        }
      }

      return 'Cart does not meet the BOGO rule requirements.';
    }

    return 'Not applicable for this cart.';
  }

  /// =======================================================
  /// Place order -> orders + order_items (+ free items)
  /// =======================================================
  Future<void> _createOrderThenPay() async {
    final lines = _lines;
    if (lines.isEmpty) return;

    setState(() {
      _placingOrder = true;
      _placeError = null;
    });

    try {
      // If a voucher is selected but became invalid, remove it
      if (_applied != null && !_voucherIsApplicable(_applied!.voucher)) {
        _applied = null;
      }

      final userId = await _resolveUserId(role: 'customer');
      final ref = _generateReference();

      final voucherId = _applied?.voucher.voucherId;
      final discountAmount = _discount;
      final variantNotes = lines
          .where((l) => (l.sizeLabel ?? '').trim().isNotEmpty)
          .map((l) => '${l.item.name} (${l.sizeLabel}) x${l.qty}')
          .join(', ');

      // 1) Create order
      final orderRow = await _client
          .from('orders')
          .insert({
            'store_id': args.storeId,
            'user_id': userId,
            'reference_number': ref,
            'status': 'pending_payment',
            'subtotal': _subtotal,
            'discount_amount': discountAmount,
            'total_amount': _total,
            'voucher_id': voucherId,
            if (variantNotes.isNotEmpty) 'notes': 'Variants: $variantNotes',
            'payment_provider': 'paymongo',
            'payment_method': 'qrph',
            'payment_status': 'pending',
          })
          .select('order_id')
          .single();

      final orderId = (orderRow['order_id'] as num).toInt();

      // 2) Create order_items + order_item_addons
      for (final line in lines) {
        final unit = line.unitTotal;
        final qty = line.qty;
        final lineSubtotal = unit * qty;

        final orderItem = await _client
            .from('order_items')
            .insert({
              'order_id': orderId,
              'menu_id': line.item.menuId,
              'quantity': qty,
              'unit_price': unit,
              'line_subtotal': lineSubtotal,
              'is_free_item': false,
              'applied_voucher_id': voucherId,
            })
            .select('order_item_id')
            .single();

        final orderItemId = (orderItem['order_item_id'] as num).toInt();

        if (line.addons.isNotEmpty) {
          final addonsPayload = line.addons.map((addon) {
            final totalQty = addon.qty * qty;
            final subtotal = addon.unitPrice * totalQty;
            return {
              'order_item_id': orderItemId,
              'addon_menu_id': addon.menuId,
              'quantity': totalQty,
              'unit_price': addon.unitPrice,
              'line_subtotal': subtotal,
            };
          }).toList();
          await _client.from('order_item_addons').insert(addonsPayload);
        }
      }

      // add free items (B1T1)
      final freeItems =
          _applied?.freeItemsPayload ?? const <Map<String, dynamic>>[];
      if (freeItems.isNotEmpty) {
        final freePayload = freeItems
            .map((f) => {...f, 'order_id': orderId})
            .toList();
        await _client.from('order_items').insert(freePayload);
      }

      if (!mounted) return;

      // 3) Create PayMongo checkout session (server-side)
      final paymongo = PayMongoService(_client);
      final checkout = await paymongo.createCheckoutSession(orderId: orderId);

      // 4) Remove active cart rows after successful order creation
      await _clearActiveCartAfterOrder(userId: userId, storeId: args.storeId);
      if (mounted) {
        setState(() => _cartByKey.clear());
      }

      if (!mounted) return;

      // 4) Open PayMongo checkout in-app (no external browser pop-out)
      Navigator.pushReplacementNamed(
        context,
        PayMongoCheckoutScreen.route,
        arguments: {
          'orderId': orderId,
          'checkoutUrl': checkout.checkoutUrl,
          'successUrl': checkout.successUrl,
          'cancelUrl': checkout.cancelUrl,
        },
      );
    } catch (e) {
      setState(() => _placeError = e.toString());
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Cart & Checkout'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
        actions: [
          if (lines.isNotEmpty)
            TextButton(
              onPressed: _placingOrder ? null : () => _clearCart(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Your Cart',
                subtitle: 'Store: ${args.storeName} • $_itemCount item(s)',
              ),
              const SizedBox(height: 10),

              if ((_placeError ?? '').trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(
                    _placeError!,
                    style: TextStyle(
                      color: Colors.red[800],
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],

              Expanded(
                child: lines.isEmpty
                    ? _EmptyCart(onBack: () => Navigator.pop(context))
                    : ListView.separated(
                        itemCount: lines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final line = lines[i];
                          return _CartItemTile(
                            line: line,
                            voucherLabel: _voucherLabelForLine(line),
                            onEdit: _placingOrder
                                ? null
                                : () => _editLineDetails(line.key),
                            onAdd: _placingOrder ? null : () => _add(line.key),
                            onRemove: _placingOrder
                                ? null
                                : () => _remove(line.key),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),

              // Voucher picker (no typing; choose from applicable)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_offer_outlined, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Voucher',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _applied == null
                                ? (_loadingVouchers
                                      ? 'Loading vouchers...'
                                      : 'Choose an available voucher')
                                : _voucherSummaryLine(_applied!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _applied == null
                                  ? Colors.grey[700]
                                  : AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: (_placingOrder || _loadingVouchers)
                          ? null
                          : () async {
                              await _openVoucherPicker();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Select',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withOpacity(0.15)),
                ),
                child: Column(
                  children: [
                    _TotalRow(label: 'Subtotal', value: _baseSubtotal),
                    const SizedBox(height: 6),
                    _TotalRow(label: 'Add-ons', value: _addonsTotal),
                    const SizedBox(height: 6),
                    _TotalRow(label: 'Discount', value: -_discount),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '₱${_total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // NOTE: PrimaryButton in your project likely expects a non-null VoidCallback,
              // so we pass a safe function always.
              PrimaryButton(
                label: _placingOrder
                    ? 'Starting payment...'
                    : lines.isEmpty
                    ? 'Cart is empty'
                    : 'Pay with QRPh • ₱${_total.toStringAsFixed(2)}',
                onPressed: () {
                  if (_placingOrder) return;
                  if (lines.isEmpty) return;
                  _createOrderThenPay();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================================================
/// UI: Empty cart
/// =======================================================
class _EmptyCart extends StatelessWidget {
  final VoidCallback onBack;
  const _EmptyCart({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 44,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 10),
            const Text(
              'Your cart is empty',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Add items from the menu to continue.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Menu'),
            ),
          ],
        ),
      ),
    );
  }
}

/// =======================================================
/// UI: Cart item tile with qty controls
/// =======================================================
class _CartItemTile extends StatelessWidget {
  final _CartLine line;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;
  final String? voucherLabel;

  const _CartItemTile({
    required this.line,
    required this.onAdd,
    required this.onRemove,
    required this.onEdit,
    this.voucherLabel,
  });

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    final qty = line.qty;
    final unitWithAddons = line.unitPrice + line.addonsUnitTotal;
    final lineTotal = (line.unitPrice * qty) + (line.addonsUnitTotal * qty);
    final addonsLabel = line.addons.isEmpty
        ? null
        : line.addons.map((a) => '${a.name} x${a.qty}').join(', ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey[200],
                        child: (item.imageUrl ?? '').trim().isNotEmpty
                            ? Image.network(
                                item.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.local_cafe_outlined,
                                  color: AppTheme.primary.withOpacity(0.6),
                                ),
                              )
                            : Icon(
                                Icons.local_cafe_outlined,
                                color: AppTheme.primary.withOpacity(0.6),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${line.sizeLabel == null ? '' : '${line.sizeLabel} • '}₱${unitWithAddons.toStringAsFixed(2)} x $qty',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (addonsLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Add-ons: $addonsLabel • +₱${line.addonsUnitTotal.toStringAsFixed(2)} each',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          if (voucherLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              voucherLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Tap item to edit details',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₱${lineTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.18)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QtyBtn(
                      icon: Icons.remove_rounded,
                      onTap: onRemove,
                      disabled: onRemove == null || qty <= 0,
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 18,
                      child: Text(
                        '$qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _QtyBtn(
                      icon: Icons.add_rounded,
                      onTap: onAdd,
                      disabled: onAdd == null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _QtyBtn({
    required this.icon,
    required this.onTap,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: disabled ? Colors.grey[350] : AppTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  const _TotalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    final abs = value.abs();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${isNegative ? '-' : ''}₱${abs.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isNegative ? Colors.green[700] : Colors.black87,
          ),
        ),
      ],
    );
  }
}

/// Voucher card used in bottom sheet
class _VoucherCard extends StatelessWidget {
  final StoreVoucherDto voucher;
  final bool enabled;
  final bool selected;
  final double previewDiscount;
  final VoidCallback? onTap;
  final String? subtitleOverride;
  final bool isUsed;

  const _VoucherCard({
    required this.voucher,
    required this.enabled,
    required this.selected,
    required this.previewDiscount,
    required this.onTap,
    this.subtitleOverride,
    this.isUsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = (voucher.title ?? '').trim().isEmpty
        ? voucher.code
        : (voucher.title ?? voucher.code);
    final subtitle = subtitleOverride ?? (voucher.details ?? '');

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withOpacity(0.45)
                    : Colors.grey.withOpacity(0.18),
                width: selected ? 2 : 1.4,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.local_offer_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle.trim().isEmpty ? '—' : subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _Chip(text: voucher.code),
                          _Chip(text: voucher.voucherType.toUpperCase()),
                          if (isUsed) _Chip(text: 'USED'),
                          if (voucher.minSpend > 0)
                            _Chip(
                              text:
                                  'Min ₱${voucher.minSpend.toStringAsFixed(0)}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (enabled)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Discount',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '-₱${previewDiscount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (selected)
                        Icon(Icons.check_circle, color: AppTheme.primary)
                      else
                        const Icon(Icons.circle_outlined, color: Colors.grey),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _AddonEditorOption {
  final int menuId;
  final String name;
  final double unitPrice;

  const _AddonEditorOption({
    required this.menuId,
    required this.name,
    required this.unitPrice,
  });
}

class _VariantEditorOption {
  final int? variantId;
  final String label;
  final double unitPrice;

  const _VariantEditorOption({
    required this.variantId,
    required this.label,
    required this.unitPrice,
  });
}

class _LineEditorResult {
  final int qty;
  final int? variantId;
  final String? sizeLabel;
  final double unitPrice;
  final List<CartAddonDto> addons;

  const _LineEditorResult({
    required this.qty,
    required this.variantId,
    required this.sizeLabel,
    required this.unitPrice,
    required this.addons,
  });
}

/// internal cart line
class _CartLine {
  final String key;
  final StoreMenuItemDto item;
  final int qty;
  final double unitPrice;
  final int? variantId;
  final String? sizeLabel;
  final List<CartAddonDto> addons;
  final int? cartItemId;

  const _CartLine({
    required this.key,
    required this.item,
    required this.qty,
    required this.unitPrice,
    required this.variantId,
    required this.sizeLabel,
    required this.addons,
    required this.cartItemId,
  });

  static const Object _noChange = Object();

  _CartLine copyWith({
    String? key,
    int? qty,
    double? unitPrice,
    Object? variantId = _noChange,
    Object? sizeLabel = _noChange,
    List<CartAddonDto>? addons,
    Object? cartItemId = _noChange,
  }) {
    return _CartLine(
      key: key ?? this.key,
      item: item,
      qty: qty ?? this.qty,
      unitPrice: unitPrice ?? this.unitPrice,
      variantId: identical(variantId, _noChange)
          ? this.variantId
          : variantId as int?,
      sizeLabel: identical(sizeLabel, _noChange)
          ? this.sizeLabel
          : sizeLabel as String?,
      addons: addons ?? this.addons,
      cartItemId: identical(cartItemId, _noChange)
          ? this.cartItemId
          : cartItemId as int?,
    );
  }

  double get addonsUnitTotal =>
      addons.fold(0.0, (sum, a) => sum + (a.unitPrice * a.qty));

  double get unitTotal => unitPrice + addonsUnitTotal;

  double get lineTotal => unitTotal * qty;
}
