import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import 'order_status_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  SupabaseClient get _client => Supabase.instance.client;

  late Future<List<StoreHistoryGroup>> _historyFuture;
  late AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _historyFuture = _fetchCompletedOrdersByStore();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
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

  Future<List<StoreHistoryGroup>> _fetchCompletedOrdersByStore() async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return const [];

    final ordersRows = await _client
        .from('orders')
        .select(
          'order_id, store_id, reference_number, total_amount, created_at, status, voucher_id, discount_amount',
        )
        .eq('user_id', userId)
        .inFilter('status', const ['completed', 'reviewed'])
        .order('created_at', ascending: false);

    final rawOrders = (ordersRows as List).cast<Map<String, dynamic>>();
    if (rawOrders.isEmpty) return const [];

    final storeIds = rawOrders
        .map((e) => (e['store_id'] as num).toInt())
        .toSet()
        .toList();

    final storesRows = await _client
        .from('stores')
        .select('store_id, store_name')
        .inFilter('store_id', storeIds);

    final storeNameById = <int, String>{};
    for (final raw in (storesRows as List)) {
      final m = (raw as Map).cast<String, dynamic>();
      storeNameById[(m['store_id'] as num).toInt()] =
          (m['store_name'] ?? 'Store').toString();
    }

    final voucherIds = rawOrders
        .map((e) => (e['voucher_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    final voucherCodeById = <int, String>{};
    if (voucherIds.isNotEmpty) {
      final voucherRows = await _client
          .from('store_vouchers')
          .select('voucher_id, code')
          .inFilter('voucher_id', voucherIds);
      for (final raw in (voucherRows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        voucherCodeById[(m['voucher_id'] as num).toInt()] =
            (m['code'] ?? '').toString();
      }
    }

    final grouped = <int, List<HistoryOrderItem>>{};
    for (final raw in rawOrders) {
      final storeId = (raw['store_id'] as num).toInt();
      final voucherId = (raw['voucher_id'] as num?)?.toInt();
      grouped.putIfAbsent(storeId, () => []);
      grouped[storeId]!.add(
        HistoryOrderItem(
          orderId: (raw['order_id'] as num).toInt(),
          referenceNumber: (raw['reference_number'] ?? '').toString(),
          totalAmount: (raw['total_amount'] as num?)?.toDouble() ?? 0,
          createdAt: DateTime.tryParse((raw['created_at'] ?? '').toString()),
          status: (raw['status'] ?? '').toString(),
          voucherId: voucherId,
          voucherCode: voucherId == null ? null : voucherCodeById[voucherId],
          discountAmount: (raw['discount_amount'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    final groups = grouped.entries.map((e) {
      return StoreHistoryGroup(
        storeId: e.key,
        storeName: storeNameById[e.key] ?? 'Store',
        orders: e.value,
      );
    }).toList();

    groups.sort((a, b) {
      final aTop = a.orders.isEmpty
          ? DateTime(1970)
          : (a.orders.first.createdAt ?? DateTime(1970));
      final bTop = b.orders.isEmpty
          ? DateTime(1970)
          : (b.orders.first.createdAt ?? DateTime(1970));
      return bTop.compareTo(aTop);
    });

    return groups;
  }

  Future<void> _refresh() async {
    setState(() => _historyFuture = _fetchCompletedOrdersByStore());
    await _historyFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Order History',
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
                          onPressed: _refresh,
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: FutureBuilder<List<StoreHistoryGroup>>(
                      future: _historyFuture,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                              strokeWidth: 3,
                            ),
                          );
                        }
                        if (snap.hasError) {
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
                                      'Failed to load history',
                                      style: TextStyle(
                                        color: Colors.red[900],
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${snap.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.red[800],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final groups = snap.data ?? const [];
                        if (groups.isEmpty) {
                          return RefreshIndicator(
                            onRefresh: _refresh,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 140),
                                Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.primary.withOpacity(0.1),
                                              AppTheme.primary.withOpacity(
                                                0.05,
                                              ),
                                            ],
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.receipt_long_outlined,
                                          size: 56,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'No completed orders yet.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: groups.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final g = groups[index];
                              return _HistoryStoreCard(
                                group: g,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          StoreHistoryOrdersScreen(group: g),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),
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

class StoreHistoryOrdersScreen extends StatefulWidget {
  final StoreHistoryGroup group;

  const StoreHistoryOrdersScreen({super.key, required this.group});

  @override
  State<StoreHistoryOrdersScreen> createState() =>
      _StoreHistoryOrdersScreenState();
}

class _StoreHistoryOrdersScreenState extends State<StoreHistoryOrdersScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _backgroundController;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
                ],
              );
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
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
                          icon: const Icon(Icons.arrow_back),
                          color: Colors.white,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.group.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.group.orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final o = widget.group.orders[index];
                        final pendingReview = o.status == 'completed';
                        return _HistoryOrderCard(
                          order: o,
                          pendingReview: pendingReview,
                          formattedDate: _fmtDate(o.createdAt),
                        );
                      },
                    ),
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

class _HistoryStoreCard extends StatelessWidget {
  final StoreHistoryGroup group;
  final VoidCallback onTap;

  const _HistoryStoreCard({
    required this.group,
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
                  child: Icon(
                    Icons.storefront_outlined,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${group.orders.length} completed order(s) • ${group.pendingReviewCount} review pending",
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group.voucherCount > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          "${group.voucherCount} order(s) with voucher",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
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


class _HistoryOrderCard extends StatelessWidget {
  final HistoryOrderItem order;
  final bool pendingReview;
  final String formattedDate;

  const _HistoryOrderCard({
    required this.order,
    required this.pendingReview,
    required this.formattedDate,
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
        borderRadius: BorderRadius.circular(18),
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
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.pushNamed(
              context,
              OrderStatusScreen.route,
              arguments: {'orderId': order.orderId},
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.referenceNumber.isEmpty
                            ? 'Order #${order.orderId}'
                            : order.referenceNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: pendingReview
                              ? Colors.orange.withOpacity(0.12)
                              : Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: pendingReview
                                ? Colors.orange.withOpacity(0.35)
                                : Colors.green.withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          pendingReview ? 'Review Pending' : 'Reviewed',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: pendingReview
                                ? Colors.orange[800]
                                : Colors.green[800],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if ((order.voucherCode ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            'Voucher ${order.voucherCode}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '₱${order.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StoreHistoryGroup {
  final int storeId;
  final String storeName;
  final List<HistoryOrderItem> orders;

  const StoreHistoryGroup({
    required this.storeId,
    required this.storeName,
    required this.orders,
  });

  int get pendingReviewCount =>
      orders.where((o) => o.status == 'completed').length;

  int get voucherCount =>
      orders.where((o) => (o.voucherCode ?? '').isNotEmpty).length;
}

class HistoryOrderItem {
  final int orderId;
  final String referenceNumber;
  final double totalAmount;
  final DateTime? createdAt;
  final String status;
  final int? voucherId;
  final String? voucherCode;
  final double discountAmount;

  const HistoryOrderItem({
    required this.orderId,
    required this.referenceNumber,
    required this.totalAmount,
    required this.createdAt,
    required this.status,
    required this.voucherId,
    required this.voucherCode,
    required this.discountAmount,
  });
}
