import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../utils/app_theme.dart';
import 'cart_screen.dart' as cart; // ✅ ALIAS to avoid name conflicts

class ViewStoreScreen extends StatefulWidget {
  static const route = '/view-store';

  final int storeId;
  const ViewStoreScreen({super.key, required this.storeId});

  @override
  State<ViewStoreScreen> createState() => _ViewStoreScreenState();
}

class _ViewStoreScreenState extends State<ViewStoreScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  SupabaseClient get _client => Supabase.instance.client;

  bool _loading = false;
  String? _error;

  StoreDetailsDto? _store;
  _StoreHoursInfo? _storeHours;
  List<_StoreScheduleRow> _weeklySchedule = const [];
  List<VoucherDto> _vouchers = [];
  List<AnnouncementDto> _announcements = [];
  List<StoreMenuItemDto> _menu = [];
  List<_LastOrderAgain> _recentOrdersAgain = [];

  CartService? _cartService;
  int? _activeCartId;
  final Map<String, _SelectedCartItem> _cartSelections = {};

  // ✅ CHANGE THIS if your menu image bucket name is different
  static const String _menuImagesBucket = 'menu_images';
  static const String _storeImagesBucket = 'store_images';

  String? _storeImageUrl(String? objectPath) {
    if (objectPath == null || objectPath.trim().isEmpty) return null;
    if (objectPath.startsWith('http://') || objectPath.startsWith('https://')) {
      return objectPath;
    }
    return _client.storage.from(_storeImagesBucket).getPublicUrl(objectPath);
  }

  // ✅ resolves store_menu_items.image_url (object path like "1/menu/xxx.jpg")
  String? _menuImageUrl(String? objectPath) {
    if (objectPath == null || objectPath.trim().isEmpty) return null;
    if (objectPath.startsWith('http://') || objectPath.startsWith('https://')) {
      return objectPath;
    }
    return _client.storage.from(_menuImagesBucket).getPublicUrl(objectPath);
  }

  String _cartKey(int menuId, int? variantId, List<_SelectedAddon> addons) {
    final addonKey = _addonsKey(addons);
    return '$menuId:${variantId ?? 0}:$addonKey';
  }

  double get total => _cartSelections.values.fold(
    0.0,
    (sum, item) => sum + (item.unitTotal * item.qty),
  );

  int get itemCount => _cartSelections.values.fold(0, (a, b) => a + b.qty);

  int _menuCount(int menuId) {
    int sum = 0;
    for (final item in _cartSelections.values) {
      if (item.menuId == menuId) sum += item.qty;
    }
    return sum;
  }

  bool get _canOrderNow {
    final hours = _storeHours;
    if (hours == null) return false;
    return hours.isAvailableToday && hours.isOpenNow;
  }

  void _showStoreClosedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Store is closed right now.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isAddonCategory(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'addons' || normalized == 'addon';
  }

  String _addonsKey(List<_SelectedAddon> addons) {
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

  List<StoreMenuItemDto> get _addonItems {
    final list = _menu.where((m) => _isAddonCategory(m.categoryName)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Map<String, List<StoreMenuItemDto>> get _menuByCategory {
    final map = <String, List<StoreMenuItemDto>>{};
    final items = [..._menu];
    items.sort((a, b) {
      final c = a.categorySort.compareTo(b.categorySort);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
    for (final m in items) {
      map.putIfAbsent(m.categoryName, () => []);
      map[m.categoryName]!.add(m);
    }
    return map;
  }

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadStorePage();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<int?> _resolveCustomerUserId() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final rows = await _client
        .from('users')
        .select('user_id')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    if ((rows as List).isEmpty) return null;
    final row = rows.first as Map;
    return (row['user_id'] as num).toInt();
  }

  Future<void> _loadPersistentCart() async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return;

    _cartService = CartService(client: _client, userId: userId);
    final activeCart = await _cartService!.getOrCreateActiveCart(
      widget.storeId,
    );
    _activeCartId = activeCart.cartId;

    final rows = await _client
        .from('cart_items')
        .select('cart_item_id, menu_id, variant_id, quantity, price')
        .eq('cart_id', activeCart.cartId);

    final cartItemIds = (rows as List)
        .map((e) => (e as Map)['cart_item_id'])
        .whereType<num>()
        .map((e) => e.toInt())
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

    final menuById = <int, StoreMenuItemDto>{
      for (final m in _menu) m.menuId: m,
    };
    final cartItemQtyById = <int, int>{
      for (final raw in rows.cast<Map<String, dynamic>>())
        (raw['cart_item_id'] as num).toInt():
            (raw['quantity'] as num?)?.toInt() ?? 0,
    };
    final addonsByCartItemId = <int, List<_SelectedAddon>>{};
    for (final raw in addonRows) {
      final m = raw.cast<String, dynamic>();
      final cartItemId = (m['cart_item_id'] as num).toInt();
      final addonMenuId = (m['addon_menu_id'] as num).toInt();
      final addonMenu = menuById[addonMenuId];
      final name = addonMenu?.name ?? 'Addon';
      final rawQty = (m['quantity'] as num?)?.toInt() ?? 0;
      final cartItemQty = cartItemQtyById[cartItemId] ?? 0;
      final normalizedQty = _normalizeAddonQtyFromDb(
        storedQty: rawQty,
        cartItemQty: cartItemQty,
      );
      addonsByCartItemId.putIfAbsent(cartItemId, () => []);
      addonsByCartItemId[cartItemId]!.add(
        _SelectedAddon(
          menuId: addonMenuId,
          name: name,
          unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
          qty: normalizedQty,
        ),
      );
    }

    final variantIds = (rows as List)
        .map((e) => ((e as Map)['variant_id'] as num?)?.toInt())
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

    final next = <String, _SelectedCartItem>{};
    for (final row in rows) {
      final m = (row as Map).cast<String, dynamic>();
      final cartItemId = (m['cart_item_id'] as num).toInt();
      final menuId = (m['menu_id'] as num).toInt();
      final menu = menuById[menuId];
      if (menu == null) continue;
      final variantId = (m['variant_id'] as num?)?.toInt();
      final qty = (m['quantity'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;
      final unitPrice =
          (m['price'] as num?)?.toDouble() ?? menu.price.toDouble();
      final addons = addonsByCartItemId[cartItemId] ?? const <_SelectedAddon>[];
      final key = _cartKey(menuId, variantId, addons);
      next[key] = _SelectedCartItem(
        menuId: menuId,
        variantId: variantId,
        sizeLabel: variantId == null ? null : variantLabelById[variantId],
        qty: qty,
        unitPrice: unitPrice,
        addons: addons,
      );
    }

    if (!mounted) return;
    setState(() {
      _cartSelections
        ..clear()
        ..addAll(next);
    });
  }

  Future<_StoreHoursData> _fetchStoreHours(int storeId, DateTime now) async {
    try {
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final rows = await _client
          .from('store_hours')
          .select(
            'store_id, day_of_week, is_closed, opening_time, closing_time, specific_date',
          )
          .eq('store_id', storeId);

      final specificByDay = <String, Map<String, dynamic>>{};
      final weeklyByDay = <int, Map<String, dynamic>>{};
      final daySet = <int>{};

      for (final raw in (rows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        final specificDate = m['specific_date']?.toString();
        final day = (m['day_of_week'] as num?)?.toInt();

        if (specificDate != null) {
          specificByDay[specificDate] = m;
        } else if (day != null) {
          weeklyByDay[day] = m;
          daySet.add(day);
        }
      }

      int sundayZeroIndex() => now.weekday % 7; // Sunday=0
      int mondayZeroIndex() => now.weekday - 1; // Monday=0
      int sundayOneIndex() => now.weekday == DateTime.saturday
          ? 0
          : now.weekday == DateTime.sunday
          ? 1
          : now.weekday + 1; // Sunday=1, Saturday=0

      int mapDisplayDayToStored(int displayDay, String mapping) {
        switch (mapping) {
          case 'monday0':
            return (displayDay + 6) % 7; // Sun->6, Mon->0
          case 'sunday1':
            return displayDay == 6 ? 0 : displayDay + 1; // Sun->1, Sat->0
          case 'sunday0':
          default:
            return displayDay; // Sun->0
        }
      }

      String mappingForDisplay() {
        int countFor(String mapping) {
          int count = 0;
          for (var displayDay = 0; displayDay <= 6; displayDay++) {
            final storedDay = mapDisplayDayToStored(displayDay, mapping);
            if (weeklyByDay.containsKey(storedDay)) count++;
          }
          return count;
        }

        final options = ['sunday0', 'monday0', 'sunday1'];
        options.sort((a, b) => countFor(b).compareTo(countFor(a)));

        // prefer mapping that matches today's row if possible
        for (final opt in options) {
          final todayStored = mapDisplayDayToStored(now.weekday % 7, opt);
          if (weeklyByDay.containsKey(todayStored)) return opt;
        }
        return options.first;
      }

      final mapping = mappingForDisplay();

      final candidates = <int>[
        sundayZeroIndex(),
        mondayZeroIndex(),
        sundayOneIndex(),
      ];

      Map<String, dynamic>? todayRow = specificByDay[today];
      if (todayRow == null) {
        for (final d in candidates) {
          if (weeklyByDay.containsKey(d)) {
            todayRow = weeklyByDay[d];
            break;
          }
        }
      }

      final todayInfo = _StoreHoursInfo.fromRow(todayRow, now);

      final schedule = <_StoreScheduleRow>[];
      for (var displayDay = 0; displayDay <= 6; displayDay++) {
        final storedDay = mapDisplayDayToStored(displayDay, mapping);
        final row = weeklyByDay[storedDay];
        final info = _StoreHoursInfo.fromRow(row, now);
        final label = row == null ? 'Closed' : info.label;
        final isClosed = row == null ? true : !info.isAvailableToday;
        schedule.add(
          _StoreScheduleRow(
            dayOfWeek: displayDay,
            dayLabel: _dayLabel(displayDay),
            label: label,
            isClosed: isClosed,
          ),
        );
      }

      return _StoreHoursData(today: todayInfo, weekly: schedule);
    } catch (_) {
      final schedule = <_StoreScheduleRow>[];
      for (var day = 0; day <= 6; day++) {
        schedule.add(
          _StoreScheduleRow(
            dayOfWeek: day,
            dayLabel: _dayLabel(day),
            label: 'Closed',
            isClosed: true,
          ),
        );
      }
      return _StoreHoursData(
        today: const _StoreHoursInfo(
          isAvailableToday: false,
          isOpenNow: false,
          label: 'Closed today',
        ),
        weekly: schedule,
      );
    }
  }

  Future<List<_MenuVariantDto>> _loadVariantsForMenu(
    StoreMenuItemDto item,
  ) async {
    try {
      final rows = await _client
          .from('store_menu_item_variants')
          .select()
          .eq('menu_id', item.menuId)
          .order('sort_order', ascending: true);

      final list = <_MenuVariantDto>[];
      for (final row in (rows as List)) {
        final m = (row as Map).cast<String, dynamic>();
        final id = (m['variant_id'] as num?)?.toInt();
        if (id == null) continue;
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
            item.price.toDouble();
        list.add(_MenuVariantDto(variantId: id, label: label, price: price));
      }
      return list;
    } catch (_) {
      return const <_MenuVariantDto>[];
    }
  }

  Future<_MenuVariantDto?> _pickVariant(
    StoreMenuItemDto item,
    List<_MenuVariantDto> variants,
  ) async {
    if (variants.isEmpty) return null;

    return showModalBottomSheet<_MenuVariantDto>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ...variants.map((v) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.label),
                    subtitle: Text('₱${v.price.toStringAsFixed(2)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(ctx, v),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<_SelectedAddon>> _pickAddons(
    StoreMenuItemDto item,
    List<StoreMenuItemDto> addons,
  ) async {
    if (addons.isEmpty) return const <_SelectedAddon>[];

    final result = await showModalBottomSheet<List<_SelectedAddon>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final counts = <int, int>{};
        return StatefulBuilder(
          builder: (context, setSheetState) {
            double addonsTotal() {
              double sum = 0;
              for (final a in addons) {
                final qty = counts[a.menuId] ?? 0;
                if (qty > 0) {
                  sum += (a.price.toDouble() * qty);
                }
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
                      'Add-ons for ${item.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 320,
                      child: ListView.separated(
                        itemCount: addons.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final addon = addons[i];
                          final qty = counts[addon.menuId] ?? 0;
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
                                        addon.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₱${addon.price.toStringAsFixed(2)} each',
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
                                    _ControlButton(
                                      icon: Icons.remove_rounded,
                                      onTap: qty <= 0
                                          ? null
                                          : () {
                                              setSheetState(() {
                                                counts[addon.menuId] = (qty - 1)
                                                    .clamp(0, 99);
                                              });
                                            },
                                      size: 30,
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 20,
                                      child: Text(
                                        '$qty',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _ControlButton(
                                      icon: Icons.add_rounded,
                                      onTap: () {
                                        setSheetState(() {
                                          counts[addon.menuId] = (qty + 1)
                                              .clamp(0, 99);
                                        });
                                      },
                                      size: 30,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
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
                          '₱${addonsTotal().toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.pop(ctx, const <_SelectedAddon>[]),
                            child: const Text('Skip'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final selected = addons
                                  .where((a) => (counts[a.menuId] ?? 0) > 0)
                                  .map((a) {
                                    final qty = counts[a.menuId] ?? 0;
                                    return _SelectedAddon(
                                      menuId: a.menuId,
                                      name: a.name,
                                      unitPrice: a.price.toDouble(),
                                      qty: qty,
                                    );
                                  })
                                  .toList();
                              Navigator.pop(ctx, selected);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                            ),
                            child: const Text('Add to cart'),
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

    return result ?? const <_SelectedAddon>[];
  }

  Future<int?> _pickItemQuantity({
    required StoreMenuItemDto item,
    required String? sizeLabel,
    required double unitPrice,
    required List<_SelectedAddon> addons,
  }) async {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        int qty = 1;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final addonLabel = addons.isEmpty
                ? 'No add-ons'
                : addons.map((a) => '${a.name} x${a.qty}').join(', ');
            final addonsUnitTotal = addons.fold<double>(
              0.0,
              (sum, a) => sum + (a.unitPrice * a.qty),
            );
            final unitTotal = unitPrice + addonsUnitTotal;
            final lineTotal = unitTotal * qty;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${sizeLabel == null ? 'Regular' : sizeLabel} • ₱${unitTotal.toStringAsFixed(2)} each',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add-ons: $addonLabel',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Quantity',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
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
                              _ControlButton(
                                icon: Icons.remove_rounded,
                                onTap: qty <= 1
                                    ? null
                                    : () {
                                        setSheetState(() {
                                          qty = (qty - 1).clamp(1, 99);
                                        });
                                      },
                                size: 34,
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 20,
                                child: Text(
                                  '$qty',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _ControlButton(
                                icon: Icons.add_rounded,
                                onTap: () {
                                  setSheetState(() {
                                    qty = (qty + 1).clamp(1, 99);
                                  });
                                },
                                size: 34,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Line total',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '₱${lineTotal.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
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
                            onPressed: () => Navigator.pop(ctx, qty),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                            ),
                            child: const Text('Add to cart'),
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

  Future<void> _addItem(StoreMenuItemDto item) async {
    if (!_canOrderNow) {
      _showStoreClosedSnack();
      return;
    }
    final cartService = _cartService;
    final activeCartId = _activeCartId;
    if (cartService == null || activeCartId == null) return;

    int? variantId;
    String? sizeLabel;
    double price = item.price.toDouble();
    if (item.hasVariants) {
      final variants = await _loadVariantsForMenu(item);
      final chosen = await _pickVariant(item, variants);
      if (chosen == null) return;
      variantId = chosen.variantId;
      sizeLabel = chosen.label;
      price = chosen.price;
    }

    List<_SelectedAddon> addons = const <_SelectedAddon>[];
    if (item.hasVariants && !_isAddonCategory(item.categoryName)) {
      addons = await _pickAddons(item, _addonItems);
    }

    final qtyToAdd = await _pickItemQuantity(
      item: item,
      sizeLabel: sizeLabel,
      unitPrice: price,
      addons: addons,
    );
    if (qtyToAdd == null || qtyToAdd <= 0) return;

    await cartService.incrementCartItem(
      cartId: activeCartId,
      storeId: item.storeId,
      menuId: item.menuId,
      variantId: variantId,
      delta: qtyToAdd,
      price: price,
    );

    final cartItem = await cartService.getCartItem(
      cartId: activeCartId,
      menuId: item.menuId,
      variantId: variantId,
    );
    if (cartItem != null) {
      await _syncCartItemAddons(
        cartItemId: cartItem.cartItemId,
        cartItemQty: cartItem.quantity,
        addons: addons,
      );
    }

    final key = _cartKey(item.menuId, variantId, addons);
    final existing = _cartSelections[key];
    if (!mounted) return;
    setState(() {
      _cartSelections[key] = _SelectedCartItem(
        menuId: item.menuId,
        variantId: variantId,
        sizeLabel: sizeLabel,
        qty: (existing?.qty ?? 0) + qtyToAdd,
        unitPrice: price,
        addons: addons,
      );
    });
  }

  Future<void> _syncCartItemAddons({
    required int cartItemId,
    required int cartItemQty,
    required List<_SelectedAddon> addons,
  }) async {
    if (addons.isEmpty) {
      await _client
          .from('cart_item_addons')
          .delete()
          .eq('cart_item_id', cartItemId);
      return;
    }

    final addonIds = addons.map((a) => a.menuId).toList();
    await _client
        .from('cart_item_addons')
        .delete()
        .eq('cart_item_id', cartItemId)
        .not('addon_menu_id', 'in', '(${addonIds.join(',')})');

    final payload = addons
        .map(
          (a) => {
            'cart_item_id': cartItemId,
            'addon_menu_id': a.menuId,
            'quantity': a.qty * cartItemQty,
            'unit_price': a.unitPrice,
            'line_subtotal': a.unitPrice * (a.qty * cartItemQty),
          },
        )
        .toList();

    await _client
        .from('cart_item_addons')
        .upsert(payload, onConflict: 'cart_item_id,addon_menu_id');
  }

  Future<void> _removeItem(StoreMenuItemDto item) async {
    final cartService = _cartService;
    final activeCartId = _activeCartId;
    if (cartService == null || activeCartId == null) return;

    final candidates = _cartSelections.values
        .where((e) => e.menuId == item.menuId && e.qty > 0)
        .toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) => b.qty.compareTo(a.qty));
    final target = candidates.first;
    final nextQty = target.qty - 1;

    await cartService.setCartItemQuantity(
      cartId: activeCartId,
      storeId: item.storeId,
      menuId: item.menuId,
      variantId: target.variantId,
      quantity: nextQty,
      price: target.unitPrice,
    );

    if (nextQty > 0) {
      final cartItem = await cartService.getCartItem(
        cartId: activeCartId,
        menuId: item.menuId,
        variantId: target.variantId,
      );
      if (cartItem != null) {
        await _syncCartItemAddons(
          cartItemId: cartItem.cartItemId,
          cartItemQty: nextQty,
          addons: target.addons,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      final key = _cartKey(item.menuId, target.variantId, target.addons);
      if (nextQty <= 0) {
        _cartSelections.remove(key);
      } else {
        _cartSelections[key] = _SelectedCartItem(
          menuId: item.menuId,
          variantId: target.variantId,
          sizeLabel: target.sizeLabel,
          qty: nextQty,
          unitPrice: target.unitPrice,
          addons: target.addons,
        );
      }
    });
  }

  Future<void> _loadStorePage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = _storeNow();
      final nowIso = now.toUtc().toIso8601String();
      final storeId = widget.storeId;

      // 1) Store details
      final storeRow = await _client
          .from('stores')
          .select(
            'store_id, store_name, store_description, store_picture_url, city, barangay, street, address_details, status',
          )
          .eq('store_id', widget.storeId)
          .single();

      final dto = StoreDetailsDto.fromMap(Map<String, dynamic>.from(storeRow));
      final store = StoreDetailsDto(
        storeId: dto.storeId,
        name: dto.name,
        city: dto.city,
        barangay: dto.barangay,
        description: dto.description,
        street: dto.street,
        addressDetails: dto.addressDetails,
        pictureUrl: _storeImageUrl(dto.pictureUrl),
      );

      // 2) Store hours (for ordering + schedule display)
      final hoursData = await _fetchStoreHours(storeId, now);

      // 3) Vouchers
      final vouchersRows = await _client
          .from('store_vouchers')
          .select('''
            voucher_id, store_id, code, title, details, voucher_type,
            discount_type, discount_value, min_spend, max_discount,
            starts_at, ends_at, is_active, created_at
          ''')
          .eq('store_id', storeId)
          .eq('is_active', true)
          .or('starts_at.lte.$nowIso,starts_at.is.null')
          .or('ends_at.gte.$nowIso,ends_at.is.null')
          .order('created_at', ascending: false)
          .limit(100);

      final vouchers = (vouchersRows as List)
          .map((e) => VoucherDto.fromMap(e as Map<String, dynamic>))
          .toList();

      // 4) Announcements
      final annRows = await _client
          .from('store_announcements')
          .select('''
            announcement_id, store_id, announcement_title, details,
            is_published, published_at, voucher_id
          ''')
          .eq('store_id', storeId)
          .eq('is_published', true)
          .or('published_at.lte.$nowIso,published_at.is.null')
          .order('published_at', ascending: false)
          .limit(50);

      final announcements = (annRows as List)
          .map((e) => AnnouncementDto.fromMap(e as Map<String, dynamic>))
          .toList();

      // 5) Menu + category join
      List<dynamic> menuRows = await _client
          .from('store_menu_items')
          .select('''
            menu_id, store_id, category_id, name, description, image_url,
            price, is_available, has_variants, created_at,
            store_categories(category_id, name, sort_order)
          ''')
          .eq('store_id', storeId)
          .eq('is_available', true)
          .order('created_at', ascending: false)
          .limit(500);

      // ✅ Convert objectPath -> public URL here
      var menu = menuRows.map((e) {
        final dto = StoreMenuItemDto.fromMap(e as Map<String, dynamic>);
        return StoreMenuItemDto(
          menuId: dto.menuId,
          storeId: dto.storeId,
          categoryId: dto.categoryId,
          name: dto.name,
          description: dto.description,
          price: dto.price,
          isAvailable: dto.isAvailable,
          hasVariants: dto.hasVariants,
          categoryName: dto.categoryName,
          categorySort: dto.categorySort,
          imageUrl: _menuImageUrl(dto.imageUrl),
        );
      }).toList();

      // Retry without is_available filter if nothing returned.
      if (menu.isEmpty) {
        menuRows = await _client
            .from('store_menu_items')
            .select('''
              menu_id, store_id, category_id, name, description, image_url,
              price, is_available, has_variants, created_at,
              store_categories(category_id, name, sort_order)
            ''')
            .eq('store_id', storeId)
            .order('created_at', ascending: false)
            .limit(500);

        menu = menuRows.map((e) {
          final dto = StoreMenuItemDto.fromMap(e as Map<String, dynamic>);
          return StoreMenuItemDto(
            menuId: dto.menuId,
            storeId: dto.storeId,
            categoryId: dto.categoryId,
            name: dto.name,
            description: dto.description,
            price: dto.price,
            isAvailable: dto.isAvailable,
            hasVariants: dto.hasVariants,
            categoryName: dto.categoryName,
            categorySort: dto.categorySort,
            imageUrl: _menuImageUrl(dto.imageUrl),
          );
        }).toList();
      }

      setState(() {
        _store = store;
        _storeHours = hoursData.today;
        _weeklySchedule = hoursData.weekly;
        _vouchers = vouchers;
        _announcements = announcements;
        _menu = menu;
        _loading = false;
      });
      await _loadRecentOrdersAgain();
      await _loadPersistentCart();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Store hours are maintained in PH time (UTC+8).
  DateTime _storeNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  Future<void> _loadRecentOrdersAgain() async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return;

    try {
      final orderRows = await _client
          .from('orders')
          .select('order_id, created_at, status')
          .eq('store_id', widget.storeId)
          .eq('user_id', userId)
          .inFilter('status', ['completed', 'reviewed'])
          .order('created_at', ascending: false)
          .limit(3);

      final rows = (orderRows as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return;

      final orderIds = rows
          .map((r) => (r['order_id'] as num).toInt())
          .toList(growable: false);

      final itemsRows = await _client
          .from('order_items')
          .select('order_item_id, order_id, menu_id, quantity')
          .inFilter('order_id', orderIds);
      final items = (itemsRows as List).cast<Map<String, dynamic>>();
      if (items.isEmpty) return;

      final orderItemIds = items
          .map((e) => (e['order_item_id'] as num).toInt())
          .toList(growable: false);

      final addonRows = orderItemIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : ((await _client
                        .from('order_item_addons')
                        .select(
                          'order_item_id, addon_menu_id, quantity, unit_price',
                        )
                        .inFilter('order_item_id', orderItemIds))
                    as List)
                .cast<Map<String, dynamic>>();

      final menuIds = items
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
                        .select('menu_id, name, price')
                        .inFilter('menu_id', allMenuIds))
                    as List)
                .cast<Map<String, dynamic>>();

      final menuById = <int, Map<String, dynamic>>{};
      for (final raw in menuRows) {
        final m = raw.cast<String, dynamic>();
        menuById[(m['menu_id'] as num).toInt()] = m;
      }

      final addonsByOrderItemId = <int, List<_SelectedAddon>>{};
      for (final raw in addonRows) {
        final m = raw.cast<String, dynamic>();
        final orderItemId = (m['order_item_id'] as num).toInt();
        final addonMenuId = (m['addon_menu_id'] as num).toInt();
        addonsByOrderItemId.putIfAbsent(orderItemId, () => []);
        addonsByOrderItemId[orderItemId]!.add(
          _SelectedAddon(
            menuId: addonMenuId,
            name: (menuById[addonMenuId]?['name'] ?? 'Addon').toString(),
            unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
            qty: (m['quantity'] as num?)?.toInt() ?? 0,
          ),
        );
      }

      final itemsByOrderId = <int, List<_OrderAgainItem>>{};
      for (final it in items) {
        final orderItemId = (it['order_item_id'] as num).toInt();
        final orderId = (it['order_id'] as num).toInt();
        final menuId = (it['menu_id'] as num).toInt();
        final qty = (it['quantity'] as num?)?.toInt() ?? 0;
        if (qty <= 0) continue;
        final menu = menuById[menuId];
        itemsByOrderId.putIfAbsent(orderId, () => []);
        itemsByOrderId[orderId]!.add(
          _OrderAgainItem(
            menuId: menuId,
            name: (menu?['name'] ?? 'Item').toString(),
            qty: qty,
            unitPrice: (menu?['price'] as num?)?.toDouble() ?? 0,
            addons:
                addonsByOrderItemId[orderItemId] ?? const <_SelectedAddon>[],
          ),
        );
      }

      final recent = <_LastOrderAgain>[];
      for (final r in rows) {
        final orderId = (r['order_id'] as num).toInt();
        final list = itemsByOrderId[orderId] ?? const <_OrderAgainItem>[];
        if (list.isEmpty) continue;
        recent.add(
          _LastOrderAgain(
            orderId: orderId,
            createdAt: _parseTs(r['created_at']),
            items: list,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _recentOrdersAgain = recent;
      });
    } catch (_) {
      // ignore
    }
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Future<void> _addOrderAgainToCart(_LastOrderAgain order) async {
    if (!_canOrderNow) {
      _showStoreClosedSnack();
      return;
    }
    final cartService = _cartService;
    final activeCartId = _activeCartId;
    if (cartService == null || activeCartId == null) return;

    for (final item in order.items) {
      final existing = await cartService.getCartItem(
        cartId: activeCartId,
        menuId: item.menuId,
        variantId: null,
      );

      if (existing == null) {
        await _client.from('cart_items').insert({
          'cart_id': activeCartId,
          'store_id': widget.storeId,
          'menu_id': item.menuId,
          'variant_id': null,
          'quantity': item.qty,
          'price': item.unitPrice,
        });
      } else {
        final nextQty = existing.quantity + item.qty;
        await _client
            .from('cart_items')
            .update({'quantity': nextQty, 'price': item.unitPrice})
            .eq('cart_item_id', existing.cartItemId);
      }

      final cartItem = await cartService.getCartItem(
        cartId: activeCartId,
        menuId: item.menuId,
        variantId: null,
      );
      if (cartItem != null && item.addons.isNotEmpty) {
        await _mergeCartItemAddons(
          cartItemId: cartItem.cartItemId,
          addons: item.addons,
        );
      }
    }

    await _loadPersistentCart();
  }

  Future<void> _mergeCartItemAddons({
    required int cartItemId,
    required List<_SelectedAddon> addons,
  }) async {
    for (final addon in addons) {
      final existing = await _client
          .from('cart_item_addons')
          .select('cart_item_addon_id, quantity')
          .eq('cart_item_id', cartItemId)
          .eq('addon_menu_id', addon.menuId)
          .maybeSingle();

      if (existing == null) {
        await _client.from('cart_item_addons').insert({
          'cart_item_id': cartItemId,
          'addon_menu_id': addon.menuId,
          'quantity': addon.qty,
          'unit_price': addon.unitPrice,
          'line_subtotal': addon.unitPrice * addon.qty,
        });
      } else {
        final nextQty =
            ((existing['quantity'] as num?)?.toInt() ?? 0) + addon.qty;
        await _client
            .from('cart_item_addons')
            .update({
              'quantity': nextQty,
              'unit_price': addon.unitPrice,
              'line_subtotal': addon.unitPrice * nextQty,
            })
            .eq(
              'cart_item_addon_id',
              (existing['cart_item_addon_id'] as num).toInt(),
            );
      }
    }
  }

  Future<void> _showOrderAgainModal(_LastOrderAgain order) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order again?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                ...order.items.map((it) {
                  final addonsLabel = it.addons.isEmpty
                      ? ''
                      : ' • Add-ons: ${it.addons.map((a) => '${a.name} x${a.qty}').join(', ')}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${it.name} x${it.qty}$addonsLabel'),
                  );
                }),
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
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _addOrderAgainToCart(order);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to cart.')),
                            );
                          }
                        },
                        child: const Text('Add to cart'),
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
  }

  Map<int, int> get _aggregatedCartByMenu {
    final map = <int, int>{};
    for (final item in _cartSelections.values) {
      map[item.menuId] = (map[item.menuId] ?? 0) + item.qty;
    }
    return map;
  }

  Map<String, List<StoreMenuItemDto>> get _menuByCategoryForDisplay {
    final map = <String, List<StoreMenuItemDto>>{};
    for (final entry in _menuByCategory.entries) {
      if (_isAddonCategory(entry.key)) continue;
      map[entry.key] = entry.value;
    }
    return map;
  }

  void _openCheckout() {
    if (!_canOrderNow) {
      _showStoreClosedSnack();
      return;
    }
    final store = _store;
    if (store == null) return;
    final cartMap = _aggregatedCartByMenu;
    if (cartMap.isEmpty) return;

    Navigator.pushNamed(
      context,
      cart.CartScreen.route,
      arguments: cart.CartArgs(
        storeId: store.storeId,
        storeName: store.name,
        cart: cartMap,
        selectedItems: _cartSelections.values.where((e) => e.qty > 0).map((e) {
          final menu = _menu.firstWhere((m) => m.menuId == e.menuId);
          return cart.CartSelectedItemDto(
            menuId: e.menuId,
            variantId: e.variantId,
            sizeLabel: e.sizeLabel,
            qty: e.qty,
            unitPrice: e.unitPrice,
            addons: e.addons
                .map(
                  (a) => cart.CartAddonDto(
                    menuId: a.menuId,
                    name: a.name,
                    qty: a.qty,
                    unitPrice: a.unitPrice,
                  ),
                )
                .toList(),
            name: menu.name,
            imageUrl: menu.imageUrl,
          );
        }).toList(),
        menu: _menu
            .map(
              (m) => cart.StoreMenuItemDto(
                menuId: m.menuId,
                name: m.name,
                price: m.price,
                imageUrl: m.imageUrl,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;

    if (_loading && store == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7FB),
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7FB),
        body: SafeArea(
          child: Center(child: Text(_error!, textAlign: TextAlign.center)),
        ),
      );
    }

    if (store == null) return const Scaffold(body: SizedBox.shrink());

    final grouped = _menuByCategoryForDisplay;
    final hours =
        _storeHours ??
        const _StoreHoursInfo(
          isAvailableToday: false,
          isOpenNow: false,
          label: 'Closed today',
        );
    final canOrderNow = _canOrderNow;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              backgroundColor: AppTheme.primary,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: const BackButton(color: Colors.white),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _CartPill(
                    count: itemCount,
                    onTap: itemCount > 0 && canOrderNow ? _openCheckout : null,
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      store.pictureUrl ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.primary,
                              AppTheme.primary.withOpacity(0.7),
                            ],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.store_outlined,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.30),
                            Colors.black.withOpacity(0.70),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _StoreInfoCard(
                        storeName: store.name,
                        subtitle: store.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: _StoreScheduleCard(hours: hours, weekly: _weeklySchedule),
            ),

            if (_announcements.isNotEmpty)
              SliverToBoxAdapter(
                child: _AnnouncementsStrip(announcements: _announcements),
              ),

            if (_vouchers.isNotEmpty)
              SliverToBoxAdapter(child: _VouchersStrip(vouchers: _vouchers)),

            if (_recentOrdersAgain.isNotEmpty)
              SliverToBoxAdapter(
                child: _OrderAgainStrip(
                  orders: _recentOrdersAgain,
                  onOrderAgain: _showOrderAgainModal,
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.15),
                            AppTheme.primary.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.restaurant_menu,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Menu',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary.withOpacity(0.15),
                            AppTheme.primary.withOpacity(0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_menu.length} items',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (grouped.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'No menu items found for this store.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),

            ...grouped.entries.expand(
              (entry) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final m = entry.value[i];
                    final count = _menuCount(m.menuId);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: _MenuItemCard(
                        item: m,
                        count: count,
                        onAdd: canOrderNow ? () => _addItem(m) : null,
                        onRemove: count > 0 ? () => _removeItem(m) : null,
                      ),
                    );
                  }, childCount: entry.value.length),
                ),
              ],
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),

      // ✅ CHECKOUT BAR
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: itemCount == 0 || !canOrderNow
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [AppTheme.primary, AppTheme.primary.withOpacity(0.85)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: itemCount == 0 || !canOrderNow
                ? const []
                : [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),

              // ✅ IMPORTANT: use cart.CartArgs + map menu into cart.StoreMenuItemDto
              onTap: itemCount > 0 && canOrderNow ? _openCheckout : null,

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.shopping_cart_checkout_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        !canOrderNow
                            ? 'Store is closed'
                            : itemCount == 0
                            ? 'Add items to checkout'
                            : 'Checkout • ₱${total.toStringAsFixed(2)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (itemCount > 0)
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------- DTOs ----------------

class _SelectedCartItem {
  final int menuId;
  final int? variantId;
  final String? sizeLabel;
  final int qty;
  final double unitPrice;
  final List<_SelectedAddon> addons;

  const _SelectedCartItem({
    required this.menuId,
    required this.variantId,
    required this.sizeLabel,
    required this.qty,
    required this.unitPrice,
    required this.addons,
  });

  double get addonsUnitTotal =>
      addons.fold(0.0, (sum, a) => sum + (a.unitPrice * a.qty));

  double get unitTotal => unitPrice + addonsUnitTotal;
}

class _MenuVariantDto {
  final int variantId;
  final String label;
  final double price;

  const _MenuVariantDto({
    required this.variantId,
    required this.label,
    required this.price,
  });
}

class _SelectedAddon {
  final int menuId;
  final String name;
  final double unitPrice;
  final int qty;

  const _SelectedAddon({
    required this.menuId,
    required this.name,
    required this.unitPrice,
    required this.qty,
  });
}

class _StoreHoursData {
  final _StoreHoursInfo today;
  final List<_StoreScheduleRow> weekly;

  const _StoreHoursData({required this.today, required this.weekly});
}

class _StoreScheduleRow {
  final int dayOfWeek; // stored index 0-6
  final String dayLabel;
  final String label;
  final bool isClosed;

  const _StoreScheduleRow({
    required this.dayOfWeek,
    required this.dayLabel,
    required this.label,
    required this.isClosed,
  });
}

class _StoreHoursInfo {
  final bool isAvailableToday;
  final bool isOpenNow;
  final String label;

  const _StoreHoursInfo({
    required this.isAvailableToday,
    required this.isOpenNow,
    required this.label,
  });

  static _StoreHoursInfo fromRow(Map<String, dynamic>? row, DateTime now) {
    if (row == null) {
      return const _StoreHoursInfo(
        isAvailableToday: false,
        isOpenNow: false,
        label: 'Closed today',
      );
    }

    final isClosed = (row['is_closed'] as bool?) ?? false;
    if (isClosed) {
      return const _StoreHoursInfo(
        isAvailableToday: false,
        isOpenNow: false,
        label: 'Closed today',
      );
    }

    final openStr = row['opening_time']?.toString();
    final closeStr = row['closing_time']?.toString();
    if (openStr == null || closeStr == null) {
      return const _StoreHoursInfo(
        isAvailableToday: false,
        isOpenNow: false,
        label: 'Closed today',
      );
    }

    DateTime? parseTime(String value) {
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return DateTime(now.year, now.month, now.day, h, m);
    }

    final openTime = parseTime(openStr);
    final closeTime = parseTime(closeStr);
    if (openTime == null || closeTime == null) {
      return const _StoreHoursInfo(
        isAvailableToday: false,
        isOpenNow: false,
        label: 'Closed today',
      );
    }

    final isOpenNow =
        (now.isAfter(openTime) && now.isBefore(closeTime)) || now == openTime;
    final label = '${_formatTime(openTime)} - ${_formatTime(closeTime)}';

    return _StoreHoursInfo(
      isAvailableToday: true,
      isOpenNow: isOpenNow,
      label: label,
    );
  }
}

String _formatTime(DateTime dt) {
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $ampm';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

String _formatDateTimeLabel(DateTime? dt, {String fallback = '-'}) {
  if (dt == null) return fallback;
  final local = dt.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[local.month - 1];
  return '$month ${local.day}, ${local.year} ${_formatTime(local)}';
}

String _dayLabel(int day) {
  switch (day) {
    case 0:
      return 'Sun';
    case 1:
      return 'Mon';
    case 2:
      return 'Tue';
    case 3:
      return 'Wed';
    case 4:
      return 'Thu';
    case 5:
      return 'Fri';
    case 6:
      return 'Sat';
    default:
      return '';
  }
}

class StoreDetailsDto {
  final int storeId;
  final String name;
  final String? description;
  final String? pictureUrl;
  final String city;
  final String barangay;
  final String? street;
  final String? addressDetails;

  const StoreDetailsDto({
    required this.storeId,
    required this.name,
    required this.city,
    required this.barangay,
    this.description,
    this.pictureUrl,
    this.street,
    this.addressDetails,
  });

  factory StoreDetailsDto.fromMap(Map<String, dynamic> m) => StoreDetailsDto(
    storeId: (m['store_id'] as num).toInt(),
    name: (m['store_name'] ?? '').toString(),
    description: m['store_description']?.toString(),
    pictureUrl: m['store_picture_url']?.toString(),
    city: (m['city'] ?? '').toString(),
    barangay: (m['barangay'] ?? '').toString(),
    street: m['street']?.toString(),
    addressDetails: m['address_details']?.toString(),
  );

  String get subtitle {
    final parts = <String>[];
    if (barangay.trim().isNotEmpty) parts.add(barangay.trim());
    if (street != null && street!.trim().isNotEmpty) parts.add(street!.trim());
    if (addressDetails != null && addressDetails!.trim().isNotEmpty) {
      parts.add(addressDetails!.trim());
    }
    return parts.isEmpty ? '$city, Bulacan' : parts.join(' • ');
  }
}

class StoreMenuItemDto {
  final int menuId;
  final int storeId;
  final int? categoryId;
  final String name;
  final String? description;
  final String? imageUrl; // FULL public URL after mapping
  final num price;
  final bool isAvailable;
  final bool hasVariants;
  final String categoryName;
  final int categorySort;

  const StoreMenuItemDto({
    required this.menuId,
    required this.storeId,
    required this.name,
    required this.price,
    required this.isAvailable,
    required this.hasVariants,
    required this.categoryName,
    required this.categorySort,
    this.categoryId,
    this.description,
    this.imageUrl,
  });

  factory StoreMenuItemDto.fromMap(Map<String, dynamic> m) {
    final cat = (m['store_categories'] as Map?)?.cast<String, dynamic>();
    return StoreMenuItemDto(
      menuId: (m['menu_id'] as num).toInt(),
      storeId: (m['store_id'] as num).toInt(),
      categoryId: (m['category_id'] as num?)?.toInt(),
      name: (m['name'] ?? '').toString(),
      description: m['description']?.toString(),
      imageUrl: m['image_url']?.toString(),
      price: (m['price'] as num?) ?? 0,
      isAvailable: (m['is_available'] as bool?) ?? true,
      hasVariants: (m['has_variants'] as bool?) ?? false,
      categoryName: (cat?['name'] ?? 'Uncategorized').toString(),
      categorySort: (cat?['sort_order'] as num?)?.toInt() ?? 9999,
    );
  }
}

class VoucherDto {
  final int voucherId;
  final int storeId;
  final String code;
  final String? title;
  final String? details;
  final DateTime? endsAt;

  const VoucherDto({
    required this.voucherId,
    required this.storeId,
    required this.code,
    this.title,
    this.details,
    this.endsAt,
  });

  factory VoucherDto.fromMap(Map<String, dynamic> m) => VoucherDto(
    voucherId: (m['voucher_id'] as num).toInt(),
    storeId: (m['store_id'] as num).toInt(),
    code: (m['code'] ?? '').toString(),
    title: m['title']?.toString(),
    details: m['details']?.toString(),
    endsAt: _parseDateTime(m['ends_at']),
  );
}

class AnnouncementDto {
  final int announcementId;
  final int storeId;
  final String title;
  final String details;
  final DateTime? publishedAt;

  const AnnouncementDto({
    required this.announcementId,
    required this.storeId,
    required this.title,
    required this.details,
    this.publishedAt,
  });

  factory AnnouncementDto.fromMap(Map<String, dynamic> m) => AnnouncementDto(
    announcementId: (m['announcement_id'] as num).toInt(),
    storeId: (m['store_id'] as num).toInt(),
    title: (m['announcement_title'] ?? '').toString(),
    details: (m['details'] ?? '').toString(),
    publishedAt: _parseDateTime(m['published_at']),
  );
}

/// ---------------- UI components ----------------

class _CartPill extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _CartPill({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreInfoCard extends StatelessWidget {
  final String storeName;
  final String subtitle;

  const _StoreInfoCard({required this.storeName, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            storeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreScheduleCard extends StatelessWidget {
  final _StoreHoursInfo hours;
  final List<_StoreScheduleRow> weekly;

  const _StoreScheduleCard({required this.hours, required this.weekly});

  @override
  Widget build(BuildContext context) {
    final statusLabel = !hours.isAvailableToday
        ? 'Closed today'
        : hours.isOpenNow
        ? 'Open now'
        : 'Closed now';
    final statusColor = hours.isOpenNow ? Colors.green : Colors.red;

    final rows = weekly.isEmpty ? const <_StoreScheduleRow>[] : weekly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hours.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Text(
                'No schedule provided.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Column(
                children: rows.map((r) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            r.dayLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            r.label.isEmpty ? 'Closed' : r.label,
                            style: TextStyle(
                              color: r.isClosed
                                  ? Colors.grey[600]
                                  : Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementsStrip extends StatelessWidget {
  final List<AnnouncementDto> announcements;
  const _AnnouncementsStrip({required this.announcements});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.75).clamp(220.0, 300.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Announcements',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: announcements.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final a = announcements[i];
                return Container(
                  width: cardWidth,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Published at: ${_formatDateTimeLabel(a.publishedAt, fallback: 'Not set')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VouchersStrip extends StatelessWidget {
  final List<VoucherDto> vouchers;
  const _VouchersStrip({required this.vouchers});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.8).clamp(240.0, 320.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Vouchers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vouchers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final v = vouchers[i];
                return Container(
                  width: cardWidth,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.title ?? 'Voucher',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          v.details ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Valid until: ${_formatDateTimeLabel(v.endsAt, fallback: 'No expiration')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          v.code,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderAgainStrip extends StatelessWidget {
  final List<_LastOrderAgain> orders;
  final ValueChanged<_LastOrderAgain> onOrderAgain;

  const _OrderAgainStrip({required this.orders, required this.onOrderAgain});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.75).clamp(220.0, 300.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Again',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final order = orders[i];
                final preview = order.items
                    .take(2)
                    .map((it) {
                      final addonsLabel = it.addons.isEmpty
                          ? ''
                          : ' • Add-ons: ${it.addons.map((a) => '${a.name} x${a.qty}').join(', ')}';
                      return '${it.name} x${it.qty}$addonsLabel';
                    })
                    .join(' • ');

                return Container(
                  width: cardWidth,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withOpacity(0.15)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              preview.isEmpty ? 'Your order' : preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to add to cart',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => onOrderAgain(order),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shopping_cart_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LastOrderAgain {
  final int orderId;
  final DateTime? createdAt;
  final List<_OrderAgainItem> items;

  const _LastOrderAgain({
    required this.orderId,
    required this.createdAt,
    required this.items,
  });
}

class _OrderAgainItem {
  final int menuId;
  final String name;
  final int qty;
  final double unitPrice;
  final List<_SelectedAddon> addons;

  const _OrderAgainItem({
    required this.menuId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.addons,
  });
}

class _MenuItemCard extends StatelessWidget {
  final StoreMenuItemDto item;
  final int count;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  const _MenuItemCard({
    required this.item,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: count > 0
              ? AppTheme.primary.withOpacity(0.3)
              : Colors.grey.withOpacity(0.15),
          width: count > 0 ? 2 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.grey[200],
                child: (item.imageUrl ?? '').trim().isEmpty
                    ? Icon(
                        Icons.local_cafe_outlined,
                        color: AppTheme.primary.withOpacity(0.5),
                        size: 36,
                      )
                    : Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.local_cafe_outlined,
                          color: AppTheme.primary.withOpacity(0.5),
                          size: 36,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),

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
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  if ((item.description ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.description ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '₱${item.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // ✅ HORIZONTAL CONTROLS
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppTheme.primary.withOpacity(0.18),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ControlButton(
                    icon: Icons.remove_rounded,
                    onTap: count > 0 ? onRemove : null,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 18,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: count > 0 ? AppTheme.primary : Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ControlButton(
                    icon: Icons.add_rounded,
                    onTap: onAdd,
                    size: 36,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: disabled ? Colors.grey[350] : AppTheme.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
