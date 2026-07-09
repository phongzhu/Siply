import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import 'order_status_screen.dart';

class HomeScreen extends StatefulWidget {
  static const route = '/home';
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// --- Simple DTOs (local only) ---
class StoreDto {
  final int storeId;
  final String name;
  final String? description;
  final String? pictureUrl;
  final String city;
  final String barangay;
  final String? street;
  final String? addressDetails;
  final String status;
  final DateTime? createdAt;
  final bool isOpenNow;
  final bool isAvailableToday;
  final String? hoursLabel;

  const StoreDto({
    required this.storeId,
    required this.name,
    required this.city,
    required this.barangay,
    required this.status,
    this.description,
    this.pictureUrl,
    this.street,
    this.addressDetails,
    this.createdAt,
    this.isOpenNow = false,
    this.isAvailableToday = false,
    this.hoursLabel,
  });

  String get subtitle {
    final parts = <String>[];
    if (barangay.trim().isNotEmpty) parts.add(barangay.trim());
    if (street != null && street!.trim().isNotEmpty) parts.add(street!.trim());
    if (addressDetails != null && addressDetails!.trim().isNotEmpty) {
      parts.add(addressDetails!.trim());
    }
    return parts.isEmpty ? 'Near you' : parts.join(' • ');
  }

  factory StoreDto.fromMap(Map<String, dynamic> m) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return StoreDto(
      storeId: (m['store_id'] as num).toInt(),
      name: (m['store_name'] ?? '').toString(),
      description: m['store_description']?.toString(),
      pictureUrl: m['store_picture_url']?.toString(),
      status: (m['status'] ?? 'active').toString(),
      city: (m['city'] ?? '').toString(),
      barangay: (m['barangay'] ?? '').toString(),
      street: m['street']?.toString(),
      addressDetails: m['address_details']?.toString(),
      createdAt: parseDt(m['created_at']),
    );
  }
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

  static _StoreHoursInfo fromRow(Map<String, dynamic> row, DateTime now) {
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
        now.isAfter(openTime) && now.isBefore(closeTime) || now == openTime;
    final label = '${_formatTime(openTime)} - ${_formatTime(closeTime)}';

    return _StoreHoursInfo(
      isAvailableToday: true,
      isOpenNow: isOpenNow,
      label: label,
    );
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}

class VoucherDto {
  final int voucherId;
  final int storeId;
  final String code;
  final String? title;
  final String? details;
  final String voucherType;
  final String? discountType;
  final num? discountValue;
  final num? minSpend;
  final num? maxDiscount;
  final bool isActive;
  final DateTime? startsAt;
  final DateTime? endsAt;

  // joined store fields (optional but useful for debug)
  final int? joinedStoreId;
  final String? joinedStoreName;
  final String? joinedStorePictureUrl;

  const VoucherDto({
    required this.voucherId,
    required this.storeId,
    required this.code,
    required this.voucherType,
    required this.isActive,
    this.title,
    this.details,
    this.discountType,
    this.discountValue,
    this.minSpend,
    this.maxDiscount,
    this.startsAt,
    this.endsAt,
    this.joinedStoreId,
    this.joinedStoreName,
    this.joinedStorePictureUrl,
  });

  factory VoucherDto.fromMap(Map<String, dynamic> m) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    final store = (m['stores'] as Map?)?.cast<String, dynamic>();

    return VoucherDto(
      voucherId: (m['voucher_id'] as num).toInt(),
      storeId: (m['store_id'] as num).toInt(),
      code: (m['code'] ?? '').toString(),
      title: m['title']?.toString(),
      details: m['details']?.toString(),
      voucherType: (m['voucher_type'] ?? 'discount').toString(),
      discountType: m['discount_type']?.toString(),
      discountValue: m['discount_value'] as num?,
      minSpend: m['min_spend'] as num?,
      maxDiscount: m['max_discount'] as num?,
      isActive: (m['is_active'] as bool?) ?? true,
      startsAt: parseDt(m['starts_at']),
      endsAt: parseDt(m['ends_at']),
      joinedStoreId: (store?['store_id'] as num?)?.toInt(),
      joinedStoreName: store?['store_name']?.toString(),
      joinedStorePictureUrl: store?['store_picture_url']?.toString(),
    );
  }
}

class AnnouncementDto {
  final int announcementId;
  final int storeId;
  final String title;
  final String details;
  final bool isPublished;
  final DateTime? publishedAt;
  final int? voucherId;

  // joined store fields (optional)
  final int? joinedStoreId;
  final String? joinedStoreName;
  final String? joinedStorePictureUrl;

  const AnnouncementDto({
    required this.announcementId,
    required this.storeId,
    required this.title,
    required this.details,
    required this.isPublished,
    this.publishedAt,
    this.voucherId,
    this.joinedStoreId,
    this.joinedStoreName,
    this.joinedStorePictureUrl,
  });

  factory AnnouncementDto.fromMap(Map<String, dynamic> m) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    final store = (m['stores'] as Map?)?.cast<String, dynamic>();

    return AnnouncementDto(
      announcementId: (m['announcement_id'] as num).toInt(),
      storeId: (m['store_id'] as num).toInt(),
      title: (m['announcement_title'] ?? '').toString(),
      details: (m['details'] ?? '').toString(),
      isPublished: (m['is_published'] as bool?) ?? true,
      publishedAt: parseDt(m['published_at']),
      voucherId: (m['voucher_id'] as num?)?.toInt(),
      joinedStoreId: (store?['store_id'] as num?)?.toInt(),
      joinedStoreName: store?['store_name']?.toString(),
      joinedStorePictureUrl: store?['store_picture_url']?.toString(),
    );
  }
}

class CurrentOrderDto {
  final int orderId;
  final int storeId;
  final String referenceNumber;
  final String status;
  final double totalAmount;
  final DateTime? createdAt;
  final String storeName;

  const CurrentOrderDto({
    required this.orderId,
    required this.storeId,
    required this.referenceNumber,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    required this.storeName,
  });

  factory CurrentOrderDto.fromMap(Map<String, dynamic> m) {
    final store = (m['stores'] as Map?)?.cast<String, dynamic>();
    final storeId = (m['store_id'] as num?)?.toInt() ?? 0;
    final storeName =
        (store?['store_name'] ?? store?['name'] ?? 'Store #$storeId')
            .toString();

    DateTime? createdAt;
    final rawCreated = m['created_at'];
    if (rawCreated != null) {
      createdAt = DateTime.tryParse(rawCreated.toString());
    }

    return CurrentOrderDto(
      orderId: (m['order_id'] as num).toInt(),
      storeId: storeId,
      referenceNumber: (m['reference_number'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt,
      storeName: storeName,
    );
  }
}

class ActiveCartItemDto {
  final int menuId;
  final int? variantId;
  final int quantity;
  final double price;
  final String menuName;
  final String? variantName;
  final List<ActiveCartAddonDto> addons;

  const ActiveCartItemDto({
    required this.menuId,
    required this.variantId,
    required this.quantity,
    required this.price,
    required this.menuName,
    required this.variantName,
    this.addons = const <ActiveCartAddonDto>[],
  });

  double get addonsUnitTotal =>
      addons.fold(0.0, (sum, a) => sum + (a.unitPrice * a.qty));

  double get unitTotal => price + addonsUnitTotal;
}

class ActiveCartAddonDto {
  final int menuId;
  final String name;
  final double unitPrice;
  final int qty;

  const ActiveCartAddonDto({
    required this.menuId,
    required this.name,
    required this.unitPrice,
    required this.qty,
  });
}

class ActiveCartDto {
  final int cartId;
  final int storeId;
  final String storeName;
  final List<ActiveCartItemDto> items;

  const ActiveCartDto({
    required this.cartId,
    required this.storeId,
    required this.storeName,
    required this.items,
  });

  int get itemCount => items.fold(0, (a, b) => a + b.quantity);
  double get total =>
      items.fold(0, (sum, i) => sum + (i.unitTotal * i.quantity));
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Helper to resolve store image object path to public URL
  String? _storeImageUrl(String? objectPath) {
    if (objectPath == null || objectPath.trim().isEmpty) return null;
    if (objectPath.startsWith('http://') || objectPath.startsWith('https://')) {
      return objectPath;
    }
    return _client.storage.from('store_images').getPublicUrl(objectPath);
  }

  late AnimationController _backgroundController;

  final List<String> _cities = const ['Baliuag', 'Pulilan', 'Bustos'];
  late String _selectedCity;

  bool _loading = false;
  String? _error;

  List<StoreDto> _stores = [];
  Map<String, List<StoreDto>> _storesByCity = {};
  List<StoreDto> _recommendedStores = [];
  List<StoreDto> _newStores = [];
  String? _recommendedCity;
  String? _recommendedBarangay;
  List<StoreDto> _orderAgainStores = [];
  final Map<int, _StoreHoursInfo> _storeHoursById = {};
  bool _addressMissing = false;
  bool _addressGateShown = false;
  List<VoucherDto> _vouchers = [];
  List<AnnouncementDto> _announcements = [];
  Map<int, double> _avgRatingByStore = {};
  Map<int, int> _ratingCountByStore = {};
  late Future<int?> _customerUserIdFuture;
  late Future<List<ActiveCartDto>> _activeCartsFuture;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _selectedCity = _cities.first;
    _customerUserIdFuture = _resolveCustomerUserId();
    _activeCartsFuture = _fetchActiveCarts();

    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshActiveCarts();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  void _refreshActiveCarts() {
    setState(() {
      _activeCartsFuture = _fetchActiveCarts();
    });
  }

  Future<Map<int, _StoreHoursInfo>> _fetchStoreHours(List<int> storeIds) async {
    final map = <int, _StoreHoursInfo>{};
    if (storeIds.isEmpty) return map;

    try {
      final now = _storeNow();
      final today =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final sundayZero = now.weekday % 7; // Sunday=0
      final mondayZero = now.weekday - 1; // Monday=0
      final sundayOne = now.weekday == DateTime.saturday
          ? 0
          : now.weekday == DateTime.sunday
          ? 1
          : now.weekday + 1; // Sunday=1, Saturday=0

      final rows = await _client
          .from('store_hours')
          .select(
            'store_id, day_of_week, is_closed, opening_time, closing_time, specific_date',
          )
          .inFilter('store_id', storeIds);

      final specificByStore = <int, Map<String, dynamic>>{};
      final weeklyByStore = <int, Map<int, Map<String, dynamic>>>{};

      for (final raw in (rows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        final storeId = (m['store_id'] as num).toInt();
        final specificDate = m['specific_date']?.toString();
        final day = (m['day_of_week'] as num?)?.toInt();

        if (specificDate != null && specificDate == today) {
          specificByStore[storeId] = m;
        } else if (specificDate == null && day != null) {
          weeklyByStore.putIfAbsent(storeId, () => {});
          weeklyByStore[storeId]![day] = m;
        }
      }

      for (final storeId in storeIds) {
        final weekly = weeklyByStore[storeId] ?? <int, Map<String, dynamic>>{};
        final row =
            specificByStore[storeId] ??
            weekly[sundayZero] ??
            weekly[mondayZero] ??
            weekly[sundayOne];
        if (row == null) continue;
        map[storeId] = _StoreHoursInfo.fromRow(row, now);
      }
    } catch (_) {
      return map;
    }

    return map;
  }

  // Store hours are maintained in PH time (UTC+8).
  DateTime _storeNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userCity = await _resolveCustomerCity();
      final address = await _resolveCustomerAddress();
      final addressCity = address['city'];
      final addressBarangay = address['barangay'];
      final addressMissing = await _resolveAddressMissing();
      if (mounted) {
        setState(() => _addressMissing = addressMissing);
      }
      if (addressMissing) {
        _maybeShowAddressGate();
      }

      // 1) STORES across supported cities
      final storesRows = await _client
          .from('stores')
          .select(
            'store_id, store_name, store_description, store_picture_url, status, city, barangay, street, address_details, created_at',
          )
          .inFilter('city', _cities)
          .eq('status', 'active')
          .order('created_at', ascending: false);

      final baseStores = (storesRows as List).map((e) {
        final dto = StoreDto.fromMap(e as Map<String, dynamic>);
        final resolvedUrl = _storeImageUrl(dto.pictureUrl);
        return StoreDto(
          storeId: dto.storeId,
          name: dto.name,
          city: dto.city,
          barangay: dto.barangay,
          status: dto.status,
          description: dto.description,
          street: dto.street,
          addressDetails: dto.addressDetails,
          pictureUrl: resolvedUrl,
          createdAt: dto.createdAt,
        );
      }).toList();

      final allStoreIdsRaw = baseStores.map((s) => s.storeId).toList();
      _storeHoursById
        ..clear()
        ..addAll(await _fetchStoreHours(allStoreIdsRaw));

      final stores = baseStores.map((s) {
        final hours = _storeHoursById[s.storeId];
        final isAvailableToday = hours?.isAvailableToday ?? false;
        final hoursLabel = hours?.label ?? 'Closed today';
        return StoreDto(
          storeId: s.storeId,
          name: s.name,
          city: s.city,
          barangay: s.barangay,
          status: s.status,
          description: s.description,
          street: s.street,
          addressDetails: s.addressDetails,
          pictureUrl: s.pictureUrl,
          createdAt: s.createdAt,
          isOpenNow: hours?.isOpenNow ?? false,
          isAvailableToday: isAvailableToday,
          hoursLabel: hoursLabel,
        );
      }).toList();

      final storesByCity = <String, List<StoreDto>>{
        for (final city in _cities) city: <StoreDto>[],
      };
      for (final store in stores) {
        if (storesByCity.containsKey(store.city)) {
          storesByCity[store.city]!.add(store);
        }
      }

      final selectedStores = storesByCity[_selectedCity] ?? const <StoreDto>[];
      final resolvedCity = _cities.contains(addressCity)
          ? addressCity
          : _cities.contains(userCity)
          ? userCity
          : _selectedCity;

      final recommendedCity = resolvedCity ?? _selectedCity;
      final cityStores = storesByCity[recommendedCity] ?? const <StoreDto>[];

      final barangay = addressBarangay?.trim();
      final hasBarangay = barangay != null && barangay.isNotEmpty;

      final recommendedStores = hasBarangay
          ? [
              ...cityStores.where(
                (s) =>
                    s.barangay.trim().toLowerCase() == barangay.toLowerCase(),
              ),
              ...cityStores.where(
                (s) =>
                    s.barangay.trim().toLowerCase() != barangay.toLowerCase(),
              ),
            ]
          : cityStores;

      final now = _storeNow();
      final newStoreCutoff = now.subtract(const Duration(days: 30));
      final newStores = cityStores
          .where((s) => (s.createdAt ?? DateTime(1970)).isAfter(newStoreCutoff))
          .toList();

      final storeIds = selectedStores.map((s) => s.storeId).toList();
      final allStoreIds = stores.map((s) => s.storeId).toList();

      final nowIso = DateTime.now().toUtc().toIso8601String();

      List<VoucherDto> vouchers = [];
      List<AnnouncementDto> announcements = [];

      if (storeIds.isNotEmpty) {
        // 2) VOUCHERS (filter by store_id list; join stores to ensure mapping is correct)
        final vouchersRows = await _client
            .from('store_vouchers')
            .select('''
              voucher_id, store_id, code, title, details, voucher_type,
              discount_type, discount_value, min_spend, max_discount,
              starts_at, ends_at, is_active,
              stores!inner(store_id, store_name, store_picture_url, city, status)
            ''')
            .eq('is_active', true)
            .inFilter('store_id', storeIds)
            // time window: starts_at <= now OR null; ends_at >= now OR null
            .or('starts_at.lte.$nowIso,starts_at.is.null')
            .or('ends_at.gte.$nowIso,ends_at.is.null')
            .eq('stores.status', 'active')
            .eq('stores.city', _selectedCity)
            .order('created_at', ascending: false)
            .limit(100);

        vouchers = (vouchersRows as List)
            .map((e) => VoucherDto.fromMap(e as Map<String, dynamic>))
            .toList();

        // 3) ANNOUNCEMENTS (filter by store_id list; join stores)
        final annRows = await _client
            .from('store_announcements')
            .select('''
              announcement_id, store_id, announcement_title, details,
              is_published, published_at, voucher_id,
              stores!inner(store_id, store_name, store_picture_url, city, status)
            ''')
            .eq('is_published', true)
            .inFilter('store_id', storeIds)
            .or('published_at.lte.$nowIso,published_at.is.null')
            .eq('stores.status', 'active')
            .eq('stores.city', _selectedCity)
            .order('published_at', ascending: false)
            .limit(50);

        announcements = (annRows as List)
            .map((e) => AnnouncementDto.fromMap(e as Map<String, dynamic>))
            .toList();
      }

      final avgRatingByStore = <int, double>{};
      final ratingCountByStore = <int, int>{};
      try {
        if (allStoreIds.isNotEmpty) {
          final reviewRows = await _client
              .from('store_order_reviews')
              .select('store_id, service_rating, drink_rating')
              .inFilter('store_id', allStoreIds);

          final sumByStore = <int, double>{};
          for (final raw in (reviewRows as List)) {
            final m = (raw as Map).cast<String, dynamic>();
            final storeId = (m['store_id'] as num).toInt();
            final service = (m['service_rating'] as num?)?.toDouble() ?? 0;
            final drink = (m['drink_rating'] as num?)?.toDouble() ?? 0;
            final overall = (service + drink) / 2.0;
            sumByStore[storeId] = (sumByStore[storeId] ?? 0) + overall;
            ratingCountByStore[storeId] =
                (ratingCountByStore[storeId] ?? 0) + 1;
          }

          for (final storeId in ratingCountByStore.keys) {
            final count = ratingCountByStore[storeId]!;
            if (count <= 0) continue;
            avgRatingByStore[storeId] = (sumByStore[storeId] ?? 0) / count;
          }
        }
      } catch (_) {
        // Table may not exist yet while migration is pending.
      }

      final orderAgainStoresRaw = await _fetchOrderAgainStores();
      final orderAgainStores = orderAgainStoresRaw;

      setState(() {
        _stores = selectedStores;
        _storesByCity = storesByCity;
        _recommendedCity = recommendedCity;
        _recommendedBarangay = barangay;
        _recommendedStores = recommendedStores;
        _newStores = newStores;
        _orderAgainStores = orderAgainStores;
        _vouchers = vouchers;
        _announcements = announcements;
        _avgRatingByStore = avgRatingByStore;
        _ratingCountByStore = ratingCountByStore;
        _loading = false;
      });
      if (mounted) {
        _refreshActiveCarts();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      if (mounted) {
        _refreshActiveCarts();
      }
    }
  }

  void _maybeShowAddressGate() {
    if (_addressGateShown || !mounted) return;
    _addressGateShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_addressMissing) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Set Your Address',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
            ),
          ),
          content: const Text(
            'Please set up your address first before you can explore the app.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushNamed('/main', arguments: {'tab': 3});
              },
              child: Text(
                'Set Address',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<int?> _resolveCustomerUserId() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final customerRows = await _client
        .from('users')
        .select('user_id')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    if ((customerRows as List).isNotEmpty) {
      final row = customerRows.first as Map;
      return (row['user_id'] as num).toInt();
    }

    final rows = await _client
        .from('users')
        .select('user_id')
        .eq('auth_user_id', authUser.id)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final row = rows.first as Map;
    return (row['user_id'] as num).toInt();
  }

  Future<String?> _resolveCustomerCity() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final preferredRows = await _client
        .from('users')
        .select('city')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    if ((preferredRows as List).isNotEmpty) {
      final row = preferredRows.first as Map;
      final city = (row['city'] ?? '').toString().trim();
      return city.isEmpty ? null : city;
    }

    final rows = await _client
        .from('users')
        .select('city')
        .eq('auth_user_id', authUser.id)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    final row = rows.first as Map;
    final city = (row['city'] ?? '').toString().trim();
    return city.isEmpty ? null : city;
  }

  Future<Map<String, String?>> _resolveCustomerAddress() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return const {'city': null, 'barangay': null};

    final preferredRows = await _client
        .from('users')
        .select('city, barangay')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    Map? row;
    if ((preferredRows as List).isNotEmpty) {
      row = preferredRows.first as Map;
    } else {
      final rows = await _client
          .from('users')
          .select('city, barangay')
          .eq('auth_user_id', authUser.id)
          .limit(1);
      if ((rows as List).isEmpty) {
        return const {'city': null, 'barangay': null};
      }
      row = rows.first as Map;
    }

    final city = (row['city'] ?? '').toString().trim();
    final barangay = (row['barangay'] ?? '').toString().trim();

    return {
      'city': city.isEmpty ? null : city,
      'barangay': barangay.isEmpty ? null : barangay,
    };
  }

  Future<bool> _resolveAddressMissing() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return true;

    final preferredRows = await _client
        .from('users')
        .select('street, barangay, city, province')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    Map? row;
    if ((preferredRows as List).isNotEmpty) {
      row = preferredRows.first as Map;
    } else {
      final rows = await _client
          .from('users')
          .select('street, barangay, city, province')
          .eq('auth_user_id', authUser.id)
          .limit(1);
      if ((rows as List).isEmpty) return true;
      row = rows.first as Map;
    }

    final barangay = (row['barangay'] ?? '').toString().trim();
    final city = (row['city'] ?? '').toString().trim();
    final province = (row['province'] ?? '').toString().trim();
    return barangay.isEmpty || city.isEmpty || province.isEmpty;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ready_for_pickup':
        return 'Ready for pickup';
      case 'preparing':
        return 'Preparing';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ready_for_pickup':
        return Colors.green;
      case 'preparing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatOrderTime(DateTime? createdAt) {
    if (createdAt == null) return '';
    final local = createdAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hh:$mm';
  }

  Future<List<ActiveCartDto>> _fetchActiveCarts() async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return const [];

    final cartRows = await _client
        .from('carts')
        .select('cart_id, store_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .order('updated_at', ascending: false);

    final cartList = (cartRows as List).cast<Map<String, dynamic>>();
    if (cartList.isEmpty) return const [];

    final cartIds = cartList
        .map((e) => (e['cart_id'] as num).toInt())
        .toList(growable: false);

    final itemRows = await _client
        .from('cart_items')
        .select('cart_item_id, cart_id, menu_id, variant_id, quantity, price')
        .inFilter('cart_id', cartIds);

    if ((itemRows as List).isEmpty) return const [];
    final rawItems = itemRows.cast<Map<String, dynamic>>();

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

    final addonMenuIds = addonRows
        .map((e) => (e['addon_menu_id'] as num).toInt())
        .toSet()
        .toList();

    final addonNameById = <int, String>{};
    if (addonMenuIds.isNotEmpty) {
      final addonMenuRows = await _client
          .from('store_menu_items')
          .select('menu_id, name')
          .inFilter('menu_id', addonMenuIds);
      for (final raw in (addonMenuRows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        addonNameById[(m['menu_id'] as num).toInt()] = (m['name'] ?? 'Addon')
            .toString();
      }
    }

    final addonsByCartItemId = <int, List<ActiveCartAddonDto>>{};
    for (final raw in addonRows) {
      final m = raw.cast<String, dynamic>();
      final cartItemId = (m['cart_item_id'] as num).toInt();
      addonsByCartItemId.putIfAbsent(cartItemId, () => []);
      final addonMenuId = (m['addon_menu_id'] as num).toInt();
      addonsByCartItemId[cartItemId]!.add(
        ActiveCartAddonDto(
          menuId: addonMenuId,
          name: addonNameById[addonMenuId] ?? 'Addon',
          unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
          qty: (m['quantity'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final storeIds = cartList
        .map((e) => (e['store_id'] as num).toInt())
        .toSet()
        .toList();
    final storeRows = await _client
        .from('stores')
        .select('store_id, store_name')
        .inFilter('store_id', storeIds);
    final storeNameById = <int, String>{};
    for (final raw in (storeRows as List)) {
      final s = (raw as Map).cast<String, dynamic>();
      storeNameById[(s['store_id'] as num).toInt()] =
          (s['store_name'] ?? 'Store').toString();
    }

    final menuIds = rawItems
        .map((e) => (e['menu_id'] as num).toInt())
        .toSet()
        .toList();
    final menuRows = await _client
        .from('store_menu_items')
        .select('menu_id, name')
        .inFilter('menu_id', menuIds);
    final menuNameById = <int, String>{};
    for (final raw in (menuRows as List)) {
      final m = (raw as Map).cast<String, dynamic>();
      menuNameById[(m['menu_id'] as num).toInt()] = (m['name'] ?? 'Item')
          .toString();
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

    final byCart = <int, List<ActiveCartItemDto>>{};
    for (final raw in rawItems) {
      final m = (raw as Map).cast<String, dynamic>();
      final cartId = (m['cart_id'] as num).toInt();
      final cartItemId = (m['cart_item_id'] as num).toInt();

      byCart.putIfAbsent(cartId, () => []);
      byCart[cartId]!.add(
        ActiveCartItemDto(
          menuId: (m['menu_id'] as num).toInt(),
          variantId: (m['variant_id'] as num?)?.toInt(),
          quantity: (m['quantity'] as num?)?.toInt() ?? 0,
          price: (m['price'] as num?)?.toDouble() ?? 0,
          menuName: menuNameById[(m['menu_id'] as num).toInt()] ?? 'Item',
          variantName: (m['variant_id'] as num?)?.toInt() == null
              ? null
              : variantLabelById[(m['variant_id'] as num).toInt()],
          addons: addonsByCartItemId[cartItemId] ?? const [],
        ),
      );
    }

    final carts = <ActiveCartDto>[];
    for (final cart in cartList) {
      final cartId = (cart['cart_id'] as num).toInt();
      final storeId = (cart['store_id'] as num).toInt();
      final items = byCart[cartId] ?? const [];
      if (items.isEmpty) continue;
      carts.add(
        ActiveCartDto(
          cartId: cartId,
          storeId: storeId,
          storeName: storeNameById[storeId] ?? 'Store',
          items: items.where((e) => e.quantity > 0).toList(),
        ),
      );
    }

    return carts.where((e) => e.items.isNotEmpty).toList();
  }

  Future<List<StoreDto>> _fetchOrderAgainStores() async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return const [];

    final orderRows = await _client
        .from('orders')
        .select('store_id, created_at, status')
        .eq('user_id', userId)
        .inFilter('status', ['completed', 'reviewed'])
        .order('created_at', ascending: false)
        .limit(50);

    final storeIds = <int>[];
    for (final raw in (orderRows as List)) {
      final m = (raw as Map).cast<String, dynamic>();
      final storeId = (m['store_id'] as num?)?.toInt();
      if (storeId == null) continue;
      if (!storeIds.contains(storeId)) {
        storeIds.add(storeId);
      }
    }

    if (storeIds.isEmpty) return const [];

    final storeRows = await _client
        .from('stores')
        .select(
          'store_id, store_name, store_description, store_picture_url, status, city, barangay, street, address_details, created_at',
        )
        .inFilter('store_id', storeIds);

    final storeById = <int, StoreDto>{};
    for (final raw in (storeRows as List)) {
      final dto = StoreDto.fromMap((raw as Map).cast<String, dynamic>());
      final resolvedUrl = _storeImageUrl(dto.pictureUrl);
      final hours = _storeHoursById[dto.storeId];
      storeById[dto.storeId] = StoreDto(
        storeId: dto.storeId,
        name: dto.name,
        city: dto.city,
        barangay: dto.barangay,
        status: dto.status,
        description: dto.description,
        street: dto.street,
        addressDetails: dto.addressDetails,
        pictureUrl: resolvedUrl,
        createdAt: dto.createdAt,
        isOpenNow: hours?.isOpenNow ?? false,
        isAvailableToday: hours?.isAvailableToday ?? false,
        hoursLabel: hours?.label,
      );
    }

    final ordered = <StoreDto>[];
    for (final id in storeIds) {
      final s = storeById[id];
      if (s != null) ordered.add(s);
    }
    return ordered;
  }

  Future<void> _openActiveCartsModal() async {
    final carts = await _fetchActiveCarts();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
                  'My cart • ${carts.length} store${carts.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: carts.isEmpty ? 1 : carts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (carts.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'No cart items yet.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        );
                      }
                      final c = carts[index];
                      return Material(
                        color: const Color(0xFFF7F7FB),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.pushNamed(
                              context,
                              '/view-store',
                              arguments: {'storeId': c.storeId},
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.storeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${c.itemCount} item(s)',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  c.items
                                      .take(2)
                                      .map((i) {
                                        final base = i.variantName == null
                                            ? '${i.menuName} x${i.quantity}'
                                            : '${i.menuName} (${i.variantName}) x${i.quantity}';
                                        if (i.addons.isEmpty) return base;
                                        final addons = i.addons
                                            .map((a) => '${a.name} x${a.qty}')
                                            .join(', ');
                                        return '$base + $addons';
                                      })
                                      .join(' • '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Total ₱${c.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    _refreshActiveCarts();
  }

  Widget _buildCartIconButton() {
    return FutureBuilder<List<ActiveCartDto>>(
      future: _activeCartsFuture,
      builder: (context, snap) {
        final carts = snap.data ?? const <ActiveCartDto>[];
        final storeCount = carts.length;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: IconButton(
                tooltip: 'Cart',
                onPressed: _openActiveCartsModal,
                icon: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colors.white,
                ),
              ),
            ),
            if (storeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                  child: Text(
                    storeCount > 99 ? '99+' : '$storeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openCurrentOrdersModal(List<CurrentOrderDto> orders) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
                  'Current orders',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final statusColor = _statusColor(order.status);
                      final mappedStoreName =
                          _storeById[order.storeId]?.name ?? order.storeName;
                      return Material(
                        color: const Color(0xFFF7F7FB),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.pushNamed(
                              context,
                              OrderStatusScreen.route,
                              arguments: {'orderId': order.orderId},
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        mappedStoreName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        order.referenceNumber.isEmpty
                                            ? 'Order #${order.orderId}'
                                            : order.referenceNumber,
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '₱${order.totalAmount.toStringAsFixed(2)} • ${_formatOrderTime(order.createdAt)}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: statusColor.withOpacity(0.35),
                                    ),
                                  ),
                                  child: Text(
                                    _statusLabel(order.status),
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// --- Mapping helpers (THIS is what fixes your "none" issue) ---
  Map<int, StoreDto> get _storeById {
    final map = <int, StoreDto>{};
    for (final s in _stores) {
      map[s.storeId] = s;
    }
    return map;
  }

  /// Stores that have at least one active voucher
  List<StoreDto> get _voucherStores {
    if (_stores.isEmpty || _vouchers.isEmpty) return [];
    final ids = _vouchers.map((v) => v.storeId).toSet();
    final list = <StoreDto>[];
    for (final id in ids) {
      final s = _storeById[id];
      if (s != null) list.add(s);
    }
    // keep stable ordering by store list order
    list.sort((a, b) => _stores.indexOf(a).compareTo(_stores.indexOf(b)));
    return list;
  }

  int _bestDiscountPercentForStore(int storeId) {
    final candidates = _vouchers.where((v) {
      if (v.storeId != storeId) return false;
      if (v.voucherType != 'discount') return false;
      if (v.discountType != 'percent') return false;
      return (v.discountValue ?? 0) > 0;
    }).toList();

    if (candidates.isEmpty) return 0;
    candidates.sort(
      (a, b) => (b.discountValue ?? 0).compareTo(a.discountValue ?? 0),
    );
    return (candidates.first.discountValue ?? 0).toInt();
  }

  bool _storeHasAnyVoucher(int storeId) {
    return _vouchers.any((v) => v.storeId == storeId);
  }

  double _averageRatingForStore(int storeId) {
    return _avgRatingByStore[storeId] ?? 0.0;
  }

  int _ratingCountForStore(int storeId) {
    return _ratingCountByStore[storeId] ?? 0;
  }

  Widget _buildStoreHorizontalList(List<StoreDto> stores) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final cardWidth = (maxWidth * 0.82).clamp(220.0, 320.0);
        return SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: stores.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final s = stores[index];
              return SizedBox(
                width: cardWidth,
                child: _StoreCard(
                  storeName: s.name,
                  subtitle: s.subtitle,
                  imageUrl: s.pictureUrl,
                  rating: _averageRatingForStore(s.storeId),
                  ratingCount: _ratingCountForStore(s.storeId),
                  etaMins: 10 + (s.storeId % 15), // placeholder
                  hasVoucher: _storeHasAnyVoucher(s.storeId),
                  discountPercent: _bestDiscountPercentForStore(s.storeId),
                  isOpenNow: s.isOpenNow,
                  hoursLabel: s.hoursLabel,
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/view-store',
                    arguments: {'storeId': s.storeId},
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cityStores = _stores;
    final voucherStores = _voucherStores;
    final recommendedCity = _recommendedCity ?? _selectedCity;
    final recommendedBarangay = _recommendedBarangay;
    final recommendedStores = _recommendedStores.isNotEmpty
        ? _recommendedStores
        : cityStores;
    final orderAgainStores = _orderAgainStores;
    final newStores = _newStores;

    final announcementItems = _announcements
        .map((a) => MapEntry(a, _storeById[a.storeId]))
        .where((entry) => entry.value != null)
        .toList();

    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                      AppTheme.primary.withOpacity(0.7),
                    ],
                    stops: [
                      0.0,
                      0.5 +
                          math.sin(_backgroundController.value * math.pi * 2) *
                              0.1,
                      1.0,
                    ],
                  ),
                ),
              );
            },
          ),

          // Decorative shapes
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -50,
                    right: -80,
                    child: Transform.rotate(
                      angle: _backgroundController.value * math.pi * 2,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 120,
                    left: -60,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadAll,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top glass header
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.25),
                            Colors.white.withOpacity(0.15),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Siply',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.location_on,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$_selectedCity, Bulacan',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              _buildCartIconButton(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_loading) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: const [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Refreshing data...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Main body
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF7F7FB),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FutureBuilder<int?>(
                              future: _customerUserIdFuture,
                              builder: (context, userSnap) {
                                final userId = userSnap.data;
                                if (userId == null) {
                                  return const SizedBox.shrink();
                                }

                                return StreamBuilder<
                                  List<Map<String, dynamic>>
                                >(
                                  stream: _client
                                      .from('orders')
                                      .stream(primaryKey: ['order_id'])
                                      .eq('user_id', userId)
                                      .order('created_at', ascending: false),
                                  builder: (context, orderSnap) {
                                    final rows = (orderSnap.data ?? const [])
                                        .where((row) {
                                          final status = (row['status'] ?? '')
                                              .toString();
                                          return status == 'preparing' ||
                                              status == 'ready_for_pickup';
                                        })
                                        .toList();
                                    if (rows.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    final orders = rows
                                        .map(
                                          (e) => CurrentOrderDto.fromMap(
                                            e.cast<String, dynamic>(),
                                          ),
                                        )
                                        .toList();

                                    final top = orders.first;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppTheme.primary.withOpacity(
                                            0.2,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.receipt_long_rounded,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${orders.length} active order${orders.length > 1 ? 's' : ''}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '${_statusLabel(top.status)} • ${top.referenceNumber.isEmpty ? '#${top.orderId}' : top.referenceNumber}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _openCurrentOrdersModal(orders),
                                            child: const Text('View'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            _SectionTitle(
                              title: 'Order Again',
                              subtitle: orderAgainStores.isEmpty
                                  ? 'No completed orders yet.'
                                  : 'Pick up from your past orders.',
                            ),
                            const SizedBox(height: 10),
                            if (orderAgainStores.isEmpty)
                              const _EmptyState(
                                title: 'No stores to reorder yet',
                                subtitle: 'Complete an order to see it here.',
                              )
                            else
                              _buildStoreHorizontalList(orderAgainStores),
                            const SizedBox(height: 18),
                            _SectionTitle(
                              title: 'Locations',
                              trailing: _CityChips(
                                cities: _cities,
                                value: _selectedCity,
                                onChanged: (v) async {
                                  setState(() => _selectedCity = v);
                                  await _loadAll();
                                },
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Announcements preview
                            _SectionTitle(
                              title: 'Latest Announcements',
                              subtitle: announcementItems.isEmpty
                                  ? 'No announcements yet.'
                                  : 'Updates from stores near you.',
                            ),
                            const SizedBox(height: 10),
                            if (announcementItems.isEmpty)
                              _EmptyState(
                                title: 'No announcements in $_selectedCity',
                                subtitle: 'Check again later.',
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final maxWidth = constraints.maxWidth;
                                  final cardWidth = (maxWidth * 0.86).clamp(
                                    240.0,
                                    320.0,
                                  );
                                  return SizedBox(
                                    height: 122,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: announcementItems.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (context, index) {
                                        final item = announcementItems[index];
                                        final store = item.value!;
                                        return SizedBox(
                                          width: cardWidth,
                                          child: _AnnouncementPreviewCard(
                                            storeName: store.name,
                                            a: item.key,
                                            onTap: () => Navigator.pushNamed(
                                              context,
                                              '/view-store',
                                              arguments: {
                                                'storeId': store.storeId,
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 18),

                            // Vouchers section (cards are STORE-based using store_id mapping)
                            _SectionTitle(
                              title: 'Discounts & Vouchers',
                              subtitle:
                                  'Online-exclusive deals to reduce waiting time.',
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 150,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: voucherStores.isEmpty
                                    ? 1
                                    : voucherStores.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  if (voucherStores.isEmpty) {
                                    return _EmptyPromoCard(
                                      message:
                                          'No promos for $_selectedCity yet.\nCheck again later!',
                                    );
                                  }

                                  final s = voucherStores[index];

                                  final discountPercent =
                                      _bestDiscountPercentForStore(s.storeId);
                                  final label = discountPercent > 0
                                      ? '$discountPercent% OFF'
                                      : (_storeHasAnyVoucher(s.storeId)
                                            ? 'VOUCHER'
                                            : 'PROMO');

                                  return _PromoCard(
                                    storeName: s.name,
                                    imageUrl: s.pictureUrl,
                                    etaMins:
                                        10 + (s.storeId % 15), // placeholder
                                    rating: _averageRatingForStore(s.storeId),
                                    ratingCount: _ratingCountForStore(
                                      s.storeId,
                                    ),
                                    discountLabel: label,
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      '/view-store',
                                      arguments: {'storeId': s.storeId},
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 18),

                            if (newStores.isNotEmpty) ...[
                              _SectionTitle(
                                title: 'Try these new stores',
                                subtitle:
                                    'Freshly opened within the last 30 days.',
                              ),
                              const SizedBox(height: 10),
                              _buildStoreHorizontalList(newStores),
                              const SizedBox(height: 18),
                            ],

                            // Recommended stores
                            _SectionTitle(
                              title: 'Recommended near $recommendedCity',
                              subtitle:
                                  (recommendedBarangay != null &&
                                      recommendedBarangay.trim().isNotEmpty)
                                  ? 'Based on your address in $recommendedBarangay.'
                                  : 'Pick a store, pay via PayMongo, then claim without lining up.',
                            ),
                            const SizedBox(height: 10),

                            if (recommendedStores.isEmpty)
                              _EmptyState(
                                title:
                                    'No stores found in ${recommendedCity.isEmpty ? 'your area' : recommendedCity}',
                                subtitle:
                                    'Try switching to Baliuag, Pulilan, or Bustos.',
                              )
                            else
                              _buildStoreHorizontalList(recommendedStores),

                            const SizedBox(height: 18),

                            // Stores by city
                            ..._cities.map((city) {
                              final storesForCity =
                                  _storesByCity[city] ?? const <StoreDto>[];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _SectionTitle(
                                    title: city,
                                    subtitle: 'Stores located in $city.',
                                  ),
                                  const SizedBox(height: 10),
                                  if (storesForCity.isEmpty)
                                    _EmptyState(
                                      title: 'No stores in $city',
                                      subtitle:
                                          'Check back later for new stores.',
                                    )
                                  else
                                    _buildStoreHorizontalList(storesForCity),
                                  const SizedBox(height: 12),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- UI COMPONENTS ----------

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const _SectionTitle({required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.sizeOf(context).width < 380;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          softWrap: true,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            softWrap: true,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.25,
            ),
          ),
        ],
      ],
    );

    Widget? trailingWidget;
    if (trailing != null) {
      trailingWidget = trailing!;
    }

    if (trailingWidget == null) return titleBlock;

    if (isSmall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: trailingWidget),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 12),
        Align(alignment: Alignment.centerRight, child: trailingWidget),
      ],
    );
  }
}

class _CityChips extends StatelessWidget {
  final List<String> cities;
  final String value;
  final ValueChanged<String> onChanged;

  const _CityChips({
    required this.cities,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: cities.map((c) {
          final selected = c == value;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                c,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.primary,
                ),
              ),
              selected: selected,
              selectedColor: AppTheme.primary,
              backgroundColor: Colors.white,
              onSelected: (_) => onChanged(c),
              side: BorderSide(
                color: selected
                    ? AppTheme.primary
                    : Colors.grey.withOpacity(0.3),
                width: 1.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AnnouncementPreviewCard extends StatelessWidget {
  final AnnouncementDto a;
  final String storeName;
  final VoidCallback onTap;

  const _AnnouncementPreviewCard({
    required this.a,
    required this.storeName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.15),
                        AppTheme.primary.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.campaign_outlined, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.2,
                        ),
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

class _PromoCard extends StatelessWidget {
  final String storeName;
  final String? imageUrl;
  final int etaMins;
  final double rating;
  final int ratingCount;
  final String discountLabel;
  final VoidCallback onTap;

  const _PromoCard({
    required this.storeName,
    required this.imageUrl,
    required this.etaMins,
    required this.rating,
    required this.ratingCount,
    required this.discountLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: (imageUrl != null && imageUrl!.trim().isNotEmpty)
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _fallback(),
                          )
                        : _fallback(),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        discountLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
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
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$etaMins min • ★ ${ratingCount > 0 ? rating.toStringAsFixed(1) : 'New'}${ratingCount > 0 ? ' ($ratingCount)' : ''}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
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
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(Icons.storefront_outlined, color: Colors.grey[400], size: 42),
    );
  }
}

class _EmptyPromoCard extends StatelessWidget {
  final String message;
  const _EmptyPromoCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.15),
                    AppTheme.primary.withOpacity(0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.local_offer_outlined, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final String storeName;
  final String subtitle;
  final String? imageUrl;
  final double rating;
  final int ratingCount;
  final int etaMins;
  final bool hasVoucher;
  final int discountPercent;
  final bool isOpenNow;
  final String? hoursLabel;
  final VoidCallback onTap;

  const _StoreCard({
    required this.storeName,
    required this.subtitle,
    required this.imageUrl,
    required this.rating,
    required this.ratingCount,
    required this.etaMins,
    required this.hasVoucher,
    required this.discountPercent,
    required this.isOpenNow,
    required this.hoursLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: (imageUrl != null && imageUrl!.trim().isNotEmpty)
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imgFallback(),
                          )
                        : _imgFallback(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (hasVoucher || discountPercent > 0)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 92),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
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
                                  discountPercent > 0
                                      ? '$discountPercent% OFF'
                                      : 'VOUCHER',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      if ((hoursLabel ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: isOpenNow
                                  ? Colors.green
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isOpenNow
                                    ? 'Open • $hoursLabel'
                                    : 'Closed • $hoursLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isOpenNow
                                      ? Colors.green[700]
                                      : Colors.grey[600],
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ratingCount > 0
                                    ? '${rating.toStringAsFixed(1)} ($ratingCount)'
                                    : 'New',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$etaMins min',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
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

  Widget _imgFallback() {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported_outlined, color: Colors.grey[400]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.2), width: 1.5),
      ),
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
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: 28,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
