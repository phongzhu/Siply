import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

import '../utils/app_theme.dart';
import 'view_store_screen.dart';

class SearchScreen extends StatefulWidget {
  static const route = '/search';
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  SupabaseClient get _client => Supabase.instance.client;
  late AnimationController _backgroundController;

  final TextEditingController _searchController = TextEditingController();
  String _selectedCity = 'All';

  bool _loading = false;
  String? _error;

  static const List<String> _baseCities = [
    'All',
    'Baliuag',
    'Pulilan',
    'Bustos',
  ];
  List<String> _cities = List<String>.from(_baseCities);
  List<StoreDto> _allStores = [];
  List<StoreDto> _filteredStores = [];
  final Map<int, _StoreHoursInfo> _storeHoursById = {};

  static const String _storeImagesBucket = 'store_images';

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _loadStores();
    _searchController.addListener(_filterStores);
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _searchController.removeListener(_filterStores);
    _searchController.dispose();
    super.dispose();
  }

  String? _storeImageUrl(String? objectPath) {
    if (objectPath == null || objectPath.trim().isEmpty) return null;
    if (objectPath.startsWith('http://') || objectPath.startsWith('https://')) {
      return objectPath;
    }
    return _client.storage.from(_storeImagesBucket).getPublicUrl(objectPath);
  }

  // Store hours are maintained in PH time (UTC+8).
  DateTime _storeNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  Future<void> _loadStores() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _client
          .from('stores')
          .select(
            'store_id, store_name, store_picture_url, city, barangay, street, address_details, status',
          )
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(500);

      final baseList =
          (rows as List)
              .map((e) => StoreDto.fromMap((e as Map).cast<String, dynamic>()))
              .toList();

      final storeIds = baseList.map((s) => s.storeId).toList();
      _storeHoursById
        ..clear()
        ..addAll(await _fetchStoreHours(storeIds));

      final list = baseList
          .map((s) {
            final hours = _storeHoursById[s.storeId];
            return StoreDto(
              storeId: s.storeId,
              name: s.name,
              city: s.city,
              barangay: s.barangay,
              street: s.street,
              addressDetails: s.addressDetails,
              pictureUrl: _storeImageUrl(s.pictureUrl),
              isOpenNow: hours?.isOpenNow ?? false,
              isAvailableToday: hours?.isAvailableToday ?? false,
              hoursLabel: hours?.label,
            );
          })
          .where((s) => s.isAvailableToday)
          .toList();

      final citySet = <String>{};
      for (final s in list) {
        if (s.city.trim().isNotEmpty) citySet.add(s.city.trim());
      }
      final cities = <String>{
        ..._baseCities,
        ...citySet.map((c) => c.trim()).where((c) => c.isNotEmpty),
      }.toList()
        ..sort();

      setState(() {
        _allStores = list;
        _cities = cities;
        _filteredStores = List.from(_allStores);
        _loading = false;
      });

      _filterStores();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _filterStores() {
    final q = _searchController.text.trim().toLowerCase();

    setState(() {
      _filteredStores = _allStores.where((store) {
        final matchesSearch =
            q.isEmpty ||
            store.name.toLowerCase().contains(q) ||
            store.subtitle.toLowerCase().contains(q);

        final matchesCity =
            _selectedCity == 'All' || store.city == _selectedCity;

        return matchesSearch && matchesCity;
      }).toList();
    });
  }

  Future<Map<int, _StoreHoursInfo>> _fetchStoreHours(
    List<int> storeIds,
  ) async {
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
        final row = specificByStore[storeId] ??
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

  void _openStore(StoreDto store) {
    Navigator.pushNamed(
      context,
      ViewStoreScreen.route,
      arguments: store.storeId,
    );
  }

  @override
  Widget build(BuildContext context) {
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

          // Main content
          SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Search Stores',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
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
                          tooltip: 'Refresh',
                          onPressed: _loading ? null : _loadStores,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Search section in header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Find a Store',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Search and filter by city',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by store name or location',
                            hintStyle: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                            prefixIcon: Container(
                              margin: const EdgeInsets.all(12),
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
                                Icons.search,
                                color: AppTheme.primary,
                                size: 22,
                              ),
                            ),
                            suffixIcon: _searchController.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      color: Colors.grey[600],
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      _filterStores();
                                    },
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // City filter chips
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _cities.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final city = _cities[index];
                            final isSelected = city == _selectedCity;
                            return _CityChip(
                              label: city,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() => _selectedCity = city);
                                _filterStores();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Content area
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
            const SizedBox(height: 16),
            Text(
              'Loading stores...',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.red.shade50,
                  Colors.red.shade100.withOpacity(0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.red.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: Colors.red[700],
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Oops! Something went wrong',
                  style: TextStyle(
                    color: Colors.red[900],
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red[800],
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade400, Colors.red.shade500],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _loadStores,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_filteredStores.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.1),
                      AppTheme.primary.withOpacity(0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.store_outlined,
                  size: 64,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'No stores found',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try adjusting your search or filter',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Results count
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
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
                  '${_filteredStores.length} ${_filteredStores.length == 1 ? 'store' : 'stores'} found',
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
        // Results list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _filteredStores.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final store = _filteredStores[index];
              return _StoreCard(store: store, onTap: () => _openStore(store));
            },
          ),
        ),
      ],
    );
  }
}

/// ===================== DTO =====================
class StoreDto {
  final int storeId;
  final String name;
  final String city;
  final String barangay;
  final String? street;
  final String? addressDetails;
  final String? pictureUrl;
  final bool isOpenNow;
  final bool isAvailableToday;
  final String? hoursLabel;

  const StoreDto({
    required this.storeId,
    required this.name,
    required this.city,
    required this.barangay,
    this.street,
    this.addressDetails,
    this.pictureUrl,
    this.isOpenNow = false,
    this.isAvailableToday = false,
    this.hoursLabel,
  });

  factory StoreDto.fromMap(Map<String, dynamic> m) => StoreDto(
    storeId: (m['store_id'] as num).toInt(),
    name: (m['store_name'] ?? '').toString(),
    city: (m['city'] ?? '').toString(),
    barangay: (m['barangay'] ?? '').toString(),
    street: m['street']?.toString(),
    addressDetails: m['address_details']?.toString(),
    pictureUrl: m['store_picture_url']?.toString(),
  );

  String get subtitle {
    final parts = <String>[];
    if (barangay.trim().isNotEmpty) parts.add(barangay.trim());
    if (street != null && street!.trim().isNotEmpty) parts.add(street!.trim());
    if (addressDetails != null && addressDetails!.trim().isNotEmpty) {
      parts.add(addressDetails!.trim());
    }
    return parts.isEmpty ? city : '$city • ${parts.join(' • ')}';
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

/// ===================== UI COMPONENTS =====================

class _CityChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CityChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [Colors.white, Colors.white.withOpacity(0.95)],
                )
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.5)
                : Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.primary : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final StoreDto store;
  final VoidCallback onTap;

  const _StoreCard({required this.store, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasImg = (store.pictureUrl ?? '').trim().isNotEmpty;

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
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Store image
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.1),
                        AppTheme.primary.withOpacity(0.05),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: hasImg
                        ? Image.network(
                            store.pictureUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.storefront_outlined,
                              color: AppTheme.primary.withOpacity(0.6),
                              size: 36,
                            ),
                          )
                        : Icon(
                            Icons.storefront_outlined,
                            color: AppTheme.primary.withOpacity(0.6),
                            size: 36,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        store.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      if (store.hoursLabel != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: store.isOpenNow
                                  ? Colors.green
                                  : Colors.grey[500],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                store.isOpenNow
                                    ? 'Open • ${store.hoursLabel}'
                                    : 'Closed • ${store.hoursLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: store.isOpenNow
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
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              store.city,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.primary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
