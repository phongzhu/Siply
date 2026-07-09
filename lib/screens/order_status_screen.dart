import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_theme.dart';
import '../widgets/order_status_step.dart';

class OrderStatusScreen extends StatefulWidget {
  static const route = '/order-status'; // make sure this matches your routes
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  SupabaseClient get _client => Supabase.instance.client;
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'siply/media_store',
  );

  int? _orderId;
  final Set<int> _reviewPromptedOrderIds = <int>{};
  bool _submittingReview = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args['orderId'] != null) {
      _orderId = (args['orderId'] as num).toInt();
    } else {
      // fallback: if you pass just an int
      if (args is int) _orderId = args;
    }
  }

  // Map your order status -> step index used by OrderStatusStep
  int _stepFromStatus(String status) {
    switch (status) {
      case 'pending_payment':
        return 0; // Ordered (waiting for payment)
      case 'paid':
        return 0; // still ordered, now paid (store may start preparing)
      case 'preparing':
        return 1; // Preparing
      case 'ready_for_pickup':
        return 2; // Collection
      case 'completed':
      case 'reviewed':
        return 3; // Completed
      case 'cancelled':
      case 'refunded':
        return 3; // show end state
      default:
        return 0;
    }
  }

  String _prettyPaymentStatus(String paymentStatus) {
    switch (paymentStatus) {
      case 'unpaid':
        return 'Unpaid';
      case 'pending':
        return 'Pending';
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      case 'refunded':
        return 'Refunded';
      default:
        return paymentStatus;
    }
  }

  Color _paymentStatusColor(String paymentStatus) {
    switch (paymentStatus) {
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'unpaid':
        return Colors.grey;
      case 'refunded':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    final s = v.toString();
    return DateTime.tryParse(s);
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$mi';
  }

  String? _menuImageUrl(String? objectPath) {
    if (objectPath == null || objectPath.trim().isEmpty) return null;
    final path = objectPath.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return _client.storage.from('menu_images').getPublicUrl(path);
  }

  Future<Map<int, List<_OrderAddonDto>>> _fetchAddonsForOrderItems(
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return const {};

    final orderItemIds = items
        .map((e) => (e['order_item_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    if (orderItemIds.isEmpty) return const {};

    final addonRows = await _client
        .from('order_item_addons')
        .select('order_item_id, addon_menu_id, quantity, unit_price')
        .inFilter('order_item_id', orderItemIds);

    final addonMenuIds = (addonRows as List)
        .map((e) => (e as Map)['addon_menu_id'] as num?)
        .whereType<num>()
        .map((e) => e.toInt())
        .toSet()
        .toList();

    final addonNameById = <int, String>{};
    if (addonMenuIds.isNotEmpty) {
      final menuRows = await _client
          .from('store_menu_items')
          .select('menu_id, name')
          .inFilter('menu_id', addonMenuIds);
      for (final raw in (menuRows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        addonNameById[(m['menu_id'] as num).toInt()] = (m['name'] ?? 'Addon')
            .toString();
      }
    }

    final byOrderItem = <int, List<_OrderAddonDto>>{};
    for (final raw in addonRows) {
      final m = (raw as Map).cast<String, dynamic>();
      final orderItemId = (m['order_item_id'] as num).toInt();
      final addonMenuId = (m['addon_menu_id'] as num).toInt();
      byOrderItem.putIfAbsent(orderItemId, () => []);
      byOrderItem[orderItemId]!.add(
        _OrderAddonDto(
          menuId: addonMenuId,
          name: addonNameById[addonMenuId] ?? 'Addon',
          qty: (m['quantity'] as num?)?.toInt() ?? 0,
          unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    return byOrderItem;
  }

  Future<_VoucherDetails?> _fetchVoucherDetails(int? voucherId) async {
    if (voucherId == null) return null;

    final row = await _client
        .from('store_vouchers')
        .select('''
          voucher_id, code, title, voucher_type,
          buy_menu_id, free_menu_id,
          store_voucher_targets(target_type, category_id, menu_id),
          store_voucher_bogo_rules(
            rule_id, buy_type, buy_menu_id, buy_category_id, buy_qty,
            get_type, get_menu_id, get_category_id, get_qty, get_discount_percent
          )
        ''')
        .eq('voucher_id', voucherId)
        .maybeSingle();

    if (row == null) return null;

    final targets = (row['store_voucher_targets'] as List? ?? const [])
        .map((e) => _VoucherTarget.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
    final rules = (row['store_voucher_bogo_rules'] as List? ?? const [])
        .map((e) => _BogoRule.fromMap((e as Map).cast<String, dynamic>()))
        .toList();

    final menuIds = <int>{};
    final categoryIds = <int>{};

    for (final t in targets) {
      if (t.menuId != null) menuIds.add(t.menuId!);
      if (t.categoryId != null) categoryIds.add(t.categoryId!);
    }

    for (final r in rules) {
      if (r.buyMenuId != null) menuIds.add(r.buyMenuId!);
      if (r.getMenuId != null) menuIds.add(r.getMenuId!);
      if (r.buyCategoryId != null) categoryIds.add(r.buyCategoryId!);
      if (r.getCategoryId != null) categoryIds.add(r.getCategoryId!);
    }

    final menuNameById = <int, String>{};
    if (menuIds.isNotEmpty) {
      final menuRows = await _client
          .from('store_menu_items')
          .select('menu_id, name')
          .inFilter('menu_id', menuIds.toList());
      for (final raw in (menuRows as List)) {
        final m = (raw as Map).cast<String, dynamic>();
        menuNameById[(m['menu_id'] as num).toInt()] = (m['name'] ?? 'Item')
            .toString();
      }
    }

    final categoryNameById = <int, String>{};
    if (categoryIds.isNotEmpty) {
      final catRows = await _client
          .from('store_categories')
          .select('category_id, name')
          .inFilter('category_id', categoryIds.toList());
      for (final raw in (catRows as List)) {
        final c = (raw as Map).cast<String, dynamic>();
        categoryNameById[(c['category_id'] as num).toInt()] =
            (c['name'] ?? 'Category').toString();
      }
    }

    return _VoucherDetails(
      voucherId: (row['voucher_id'] as num).toInt(),
      code: (row['code'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      voucherType: (row['voucher_type'] ?? '').toString(),
      buyMenuId: (row['buy_menu_id'] as num?)?.toInt(),
      freeMenuId: (row['free_menu_id'] as num?)?.toInt(),
      targets: targets,
      bogoRules: rules,
      menuNameById: menuNameById,
      categoryNameById: categoryNameById,
    );
  }

  bool _isOrderItemEligibleForVoucher(
    _VoucherDetails v,
    int menuId,
    int? categoryId,
  ) {
    switch (v.voucherType) {
      case 'discount':
        if (v.targets.isEmpty) return true;
        if (v.targets.any((t) => t.targetType == 'all_items')) return true;
        for (final t in v.targets) {
          if (t.targetType == 'menu_item' && t.menuId == menuId) return true;
          if (t.targetType == 'category' && t.categoryId == categoryId) {
            return true;
          }
        }
        return false;
      case 'b1t1':
        return menuId == v.buyMenuId || menuId == v.freeMenuId;
      case 'bogo':
        for (final r in v.bogoRules) {
          if (r.buyType == 'menu_item' && r.buyMenuId == menuId) return true;
          if (r.buyType == 'category' && r.buyCategoryId == categoryId) {
            return true;
          }
          if (r.getType == 'menu_item' && r.getMenuId == menuId) return true;
          if (r.getType == 'category' && r.getCategoryId == categoryId) {
            return true;
          }
        }
        return false;
      default:
        return false;
    }
  }

  String _voucherTargetsLabel(_VoucherDetails v) {
    if (v.targets.isEmpty) return 'All items';
    if (v.targets.any((t) => t.targetType == 'all_items')) return 'All items';

    final parts = <String>[];
    for (final t in v.targets) {
      if (t.targetType == 'menu_item' && t.menuId != null) {
        parts.add(v.menuNameById[t.menuId!] ?? 'Item');
      }
      if (t.targetType == 'category' && t.categoryId != null) {
        parts.add(v.categoryNameById[t.categoryId!] ?? 'Category');
      }
    }
    return parts.isEmpty ? 'Selected items' : parts.join(', ');
  }

  Future<_OrderItemsContext> _buildOrderItemsContext(
    List<Map<String, dynamic>> items,
    int? voucherId,
  ) async {
    final menuRows = await _fetchMenuDetailsForOrderItems(items);
    final menuById = <int, Map<String, dynamic>>{};
    final categoryByMenuId = <int, int?>{};
    for (final r in menuRows) {
      menuById[(r['menu_id'] as num).toInt()] = r;
      categoryByMenuId[(r['menu_id'] as num).toInt()] =
          (r['category_id'] as num?)?.toInt();
    }

    final addonsByOrderItemId = await _fetchAddonsForOrderItems(items);
    final voucherDetails = await _fetchVoucherDetails(voucherId);

    return _OrderItemsContext(
      menuById: menuById,
      addonsByOrderItemId: addonsByOrderItemId,
      categoryByMenuId: categoryByMenuId,
      voucherDetails: voucherDetails,
    );
  }

  String _sanitizeFileSegment(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (cleaned.isEmpty) return 'receipt';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  Future<String> _resolveStoreName(int storeId) async {
    if (storeId <= 0) return 'Store';
    final row = await _client
        .from('stores')
        .select('store_name')
        .eq('store_id', storeId)
        .maybeSingle();
    return (row?['store_name'] ?? 'Store').toString();
  }

  String _php(double value) => 'PHP ${value.toStringAsFixed(2)}';

  double _measureTextHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }

  double _drawText({
    required Canvas canvas,
    required String text,
    required Offset offset,
    required TextStyle style,
    required double maxWidth,
    TextAlign textAlign = TextAlign.left,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
    return painter.height;
  }

  double _measureReceiptItemCardHeight({
    required _ReceiptLineItem item,
    required double contentWidth,
    required TextStyle itemNameStyle,
    required TextStyle itemDetailStyle,
    required TextStyle addonStyle,
    required TextStyle priceStyle,
  }) {
    const horizontalPadding = 18.0;
    const topBottomPadding = 16.0;
    const gapAfterName = 8.0;
    const gapAfterDetail = 8.0;
    const gapBetweenAddons = 4.0;

    final bodyWidth = contentWidth - (horizontalPadding * 2);
    final priceWidth = 240.0;
    final nameWidth = bodyWidth - priceWidth - 14;

    final nameHeight = _measureTextHeight(
      text: item.name,
      style: itemNameStyle,
      maxWidth: nameWidth,
      maxLines: 2,
    );
    final priceHeight = _measureTextHeight(
      text: _php(item.lineTotal),
      style: priceStyle,
      maxWidth: priceWidth,
      maxLines: 1,
    );
    final detailHeight = _measureTextHeight(
      text: item.isFree
          ? 'Qty ${item.qty} • FREE ITEM'
          : 'Qty ${item.qty} • ${_php(item.unitPrice)} each',
      style: itemDetailStyle,
      maxWidth: bodyWidth,
      maxLines: 2,
    );

    var height =
        topBottomPadding +
        (nameHeight > priceHeight ? nameHeight : priceHeight) +
        gapAfterName +
        detailHeight;

    if (item.addons.isNotEmpty) {
      height += gapAfterDetail;
      for (var i = 0; i < item.addons.length; i++) {
        final addon = item.addons[i];
        final addonLine =
            '+ ${addon.name} x${addon.qty} • ${_php(addon.unitPrice)}';
        height += _measureTextHeight(
          text: addonLine,
          style: addonStyle,
          maxWidth: bodyWidth,
          maxLines: 2,
        );
        if (i < item.addons.length - 1) {
          height += gapBetweenAddons;
        }
      }
    }

    return height + topBottomPadding;
  }

  Future<Uint8List> _buildReceiptPngBytes({
    required int orderId,
    required String reference,
    required String storeName,
    required String paymentStatus,
    required DateTime? createdAt,
    required double subtotal,
    required double discount,
    required double total,
    required List<_ReceiptLineItem> lineItems,
    required _VoucherDetails? voucherDetails,
  }) async {
    const canvasWidth = 1080.0;
    const pageInset = 26.0;
    const cardInset = 28.0;
    final pageWidth = canvasWidth - (pageInset * 2);
    final contentWidth = pageWidth - (cardInset * 2);

    final titleStyle = const TextStyle(
      color: Colors.white,
      fontSize: 48,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
    );
    final headerMetaStyle = TextStyle(
      color: Colors.white.withOpacity(0.92),
      fontSize: 24,
      fontWeight: FontWeight.w600,
    );
    final labelStyle = const TextStyle(
      color: Color(0xFF6B7280),
      fontSize: 23,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = const TextStyle(
      color: Color(0xFF111827),
      fontSize: 24,
      fontWeight: FontWeight.w700,
    );
    final sectionTitleStyle = const TextStyle(
      color: Color(0xFF0F172A),
      fontSize: 30,
      fontWeight: FontWeight.w800,
    );
    final itemNameStyle = const TextStyle(
      color: Color(0xFF111827),
      fontSize: 28,
      fontWeight: FontWeight.w800,
    );
    final itemDetailStyle = const TextStyle(
      color: Color(0xFF4B5563),
      fontSize: 22,
      fontWeight: FontWeight.w600,
    );
    final addonStyle = const TextStyle(
      color: Color(0xFF374151),
      fontSize: 21,
      fontWeight: FontWeight.w600,
    );
    final itemPriceStyle = TextStyle(
      color: AppTheme.primary,
      fontSize: 27,
      fontWeight: FontWeight.w800,
    );
    final totalStrongStyle = TextStyle(
      color: AppTheme.primary,
      fontSize: 30,
      fontWeight: FontWeight.w900,
    );
    final footerStyle = const TextStyle(
      color: Color(0xFF6B7280),
      fontSize: 20,
      fontWeight: FontWeight.w600,
    );

    var itemsHeight = 0.0;
    for (final item in lineItems) {
      itemsHeight += _measureReceiptItemCardHeight(
        item: item,
        contentWidth: contentWidth,
        itemNameStyle: itemNameStyle,
        itemDetailStyle: itemDetailStyle,
        addonStyle: addonStyle,
        priceStyle: itemPriceStyle,
      );
    }
    if (lineItems.length > 1) {
      itemsHeight += (lineItems.length - 1) * 12;
    }

    final hasVoucher = voucherDetails != null;
    final voucherHeight = hasVoucher ? 128.0 : 0.0;

    final estimatedHeight =
        70 + // top gap
        190 + // header
        24 + // space
        230 + // order info card
        20 +
        voucherHeight +
        (hasVoucher ? 20 : 0) +
        40 + // items title
        12 +
        itemsHeight +
        22 +
        190 + // totals card
        18 +
        40 + // generated
        80; // bottom

    final canvasHeight = estimatedHeight.clamp(1400.0, 7600.0);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
      Paint()..color = const Color(0xFFF3F7FC),
    );

    final pageRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pageInset,
        pageInset,
        pageWidth,
        canvasHeight - (pageInset * 2),
      ),
      const Radius.circular(28),
    );
    canvas.drawRRect(
      pageRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    final headerRect = Rect.fromLTWH(pageInset, pageInset, pageWidth, 190);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        headerRect,
        topLeft: const Radius.circular(28),
        topRight: const Radius.circular(28),
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          headerRect.topLeft,
          headerRect.bottomRight,
          <Color>[AppTheme.primary, AppTheme.primary.withOpacity(0.85)],
        ),
    );

    final headerX = pageInset + cardInset;
    _drawText(
      canvas: canvas,
      text: 'SIPLY RECEIPT',
      offset: Offset(headerX, pageInset + 34),
      style: titleStyle,
      maxWidth: contentWidth,
      maxLines: 1,
    );

    final refLabel = reference.trim().isEmpty
        ? 'Order #$orderId'
        : reference.trim();
    _drawText(
      canvas: canvas,
      text: refLabel,
      offset: Offset(headerX, pageInset + 106),
      style: headerMetaStyle,
      maxWidth: contentWidth * 0.74,
      maxLines: 1,
    );

    final statusColor = _paymentStatusColor(paymentStatus);
    final statusText = _prettyPaymentStatus(paymentStatus);
    final statusWidth = 210.0;
    final statusRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        pageInset + pageWidth - cardInset - statusWidth,
        pageInset + 36,
        statusWidth,
        54,
      ),
      const Radius.circular(26),
    );
    canvas.drawRRect(
      statusRect,
      Paint()..color = statusColor.withOpacity(0.16),
    );
    _drawText(
      canvas: canvas,
      text: statusText,
      offset: Offset(statusRect.left + 22, statusRect.top + 14),
      style: TextStyle(
        color: statusColor,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: statusWidth - 44,
      maxLines: 1,
      textAlign: TextAlign.center,
    );

    var y = pageInset + 190 + 24;
    final infoCardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pageInset + cardInset, y, contentWidth, 230),
      const Radius.circular(20),
    );
    canvas.drawRRect(infoCardRect, Paint()..color = const Color(0xFFF8FAFD));
    canvas.drawRRect(
      infoCardRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFE2E8F0),
    );

    var infoY = y + 20;
    final rowLabelWidth = contentWidth * 0.36;
    final rowValueWidth = contentWidth - rowLabelWidth - 16;
    double drawInfoRow(
      String label,
      String value, {
      TextStyle? valueStyleOverride,
    }) {
      final labelHeight = _drawText(
        canvas: canvas,
        text: label,
        offset: Offset(pageInset + cardInset + 16, infoY),
        style: labelStyle,
        maxWidth: rowLabelWidth,
        maxLines: 1,
      );
      final valueHeight = _drawText(
        canvas: canvas,
        text: value,
        offset: Offset(pageInset + cardInset + 16 + rowLabelWidth + 16, infoY),
        style: valueStyleOverride ?? valueStyle,
        maxWidth: rowValueWidth,
        maxLines: 1,
        textAlign: TextAlign.right,
      );
      final rowHeight = labelHeight > valueHeight ? labelHeight : valueHeight;
      infoY += rowHeight + 12;
      return rowHeight;
    }

    drawInfoRow('Order ID', orderId.toString());
    drawInfoRow('Store', storeName);
    drawInfoRow('Order Time', _fmtDateTime(createdAt));
    drawInfoRow('Payment', statusText);
    drawInfoRow('Reference', refLabel);

    y += 230 + 20;

    if (hasVoucher) {
      final voucherTitle = voucherDetails.title.trim().isEmpty
          ? voucherDetails.code
          : '${voucherDetails.title} (${voucherDetails.code})';
      final voucherRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pageInset + cardInset, y, contentWidth, voucherHeight),
        const Radius.circular(18),
      );
      canvas.drawRRect(voucherRect, Paint()..color = const Color(0xFFFFF8EC));
      canvas.drawRRect(
        voucherRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFD28A),
      );
      _drawText(
        canvas: canvas,
        text: 'Voucher Applied',
        offset: Offset(pageInset + cardInset + 16, y + 14),
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
        maxWidth: contentWidth - 32,
        maxLines: 1,
      );
      _drawText(
        canvas: canvas,
        text: voucherTitle,
        offset: Offset(pageInset + cardInset + 16, y + 44),
        style: const TextStyle(
          color: Color(0xFF7C2D12),
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        maxWidth: contentWidth - 32,
        maxLines: 1,
      );
      _drawText(
        canvas: canvas,
        text: 'Applies to: ${_voucherTargetsLabel(voucherDetails)}',
        offset: Offset(pageInset + cardInset + 16, y + 76),
        style: const TextStyle(
          color: Color(0xFF9A3412),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        maxWidth: contentWidth - 32,
        maxLines: 2,
      );
      y += voucherHeight + 20;
    }

    _drawText(
      canvas: canvas,
      text: 'Items',
      offset: Offset(pageInset + cardInset, y),
      style: sectionTitleStyle,
      maxWidth: contentWidth,
      maxLines: 1,
    );
    y += 52;

    for (final item in lineItems) {
      final itemHeight = _measureReceiptItemCardHeight(
        item: item,
        contentWidth: contentWidth,
        itemNameStyle: itemNameStyle,
        itemDetailStyle: itemDetailStyle,
        addonStyle: addonStyle,
        priceStyle: itemPriceStyle,
      );
      final itemRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pageInset + cardInset, y, contentWidth, itemHeight),
        const Radius.circular(18),
      );
      canvas.drawRRect(itemRect, Paint()..color = const Color(0xFFF9FBFE));
      canvas.drawRRect(
        itemRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFE2E8F0),
      );

      final itemX = pageInset + cardInset + 18;
      final innerWidth = contentWidth - 36;
      final priceWidth = 240.0;
      final nameWidth = innerWidth - priceWidth - 14;
      var itemY = y + 16;

      final nameHeight = _drawText(
        canvas: canvas,
        text: item.name,
        offset: Offset(itemX, itemY),
        style: itemNameStyle,
        maxWidth: nameWidth,
        maxLines: 2,
      );

      _drawText(
        canvas: canvas,
        text: _php(item.lineTotal),
        offset: Offset(itemX + nameWidth + 14, itemY),
        style: itemPriceStyle,
        maxWidth: priceWidth,
        maxLines: 1,
        textAlign: TextAlign.right,
      );

      itemY += nameHeight + 8;

      final detailText = item.isFree
          ? 'Qty ${item.qty} • FREE ITEM'
          : 'Qty ${item.qty} • ${_php(item.unitPrice)} each';
      final detailHeight = _drawText(
        canvas: canvas,
        text: detailText,
        offset: Offset(itemX, itemY),
        style: itemDetailStyle,
        maxWidth: innerWidth,
        maxLines: 2,
      );
      itemY += detailHeight;

      if (item.addons.isNotEmpty) {
        itemY += 8;
        for (final addon in item.addons) {
          final addonLine =
              '+ ${addon.name} x${addon.qty} • ${_php(addon.unitPrice)}';
          final addonHeight = _drawText(
            canvas: canvas,
            text: addonLine,
            offset: Offset(itemX, itemY),
            style: addonStyle,
            maxWidth: innerWidth,
            maxLines: 2,
          );
          itemY += addonHeight + 4;
        }
      }

      y += itemHeight + 12;
    }

    y += 10;
    final totalsRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pageInset + cardInset, y, contentWidth, 190),
      const Radius.circular(20),
    );
    canvas.drawRRect(totalsRect, Paint()..color = const Color(0xFFF1F7FF));
    canvas.drawRRect(
      totalsRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFCCE4FF),
    );

    var totalsY = y + 22;
    double drawTotalRow(
      String label,
      String value, {
      bool strong = false,
      Color? valueColor,
    }) {
      final ls = strong
          ? labelStyle.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            )
          : labelStyle;
      final vs = strong
          ? totalStrongStyle
          : valueStyle.copyWith(color: valueColor ?? valueStyle.color);

      final lh = _drawText(
        canvas: canvas,
        text: label,
        offset: Offset(pageInset + cardInset + 16, totalsY),
        style: ls,
        maxWidth: rowLabelWidth,
        maxLines: 1,
      );
      final vh = _drawText(
        canvas: canvas,
        text: value,
        offset: Offset(
          pageInset + cardInset + 16 + rowLabelWidth + 16,
          totalsY,
        ),
        style: vs,
        maxWidth: rowValueWidth,
        maxLines: 1,
        textAlign: TextAlign.right,
      );
      final rh = lh > vh ? lh : vh;
      totalsY += rh + (strong ? 0 : 12);
      return rh;
    }

    drawTotalRow('Subtotal', _php(subtotal));
    drawTotalRow(
      'Discount',
      discount > 0 ? '-${_php(discount)}' : _php(0),
      valueColor: discount > 0 ? const Color(0xFF166534) : null,
    );

    final dividerY = totalsY + 4;
    canvas.drawLine(
      Offset(pageInset + cardInset + 16, dividerY),
      Offset(pageInset + cardInset + contentWidth - 16, dividerY),
      Paint()
        ..color = const Color(0xFFBFD8F8)
        ..strokeWidth = 1.3,
    );
    totalsY = dividerY + 14;
    drawTotalRow('Total', _php(total), strong: true);

    y += 190 + 18;
    _drawText(
      canvas: canvas,
      text: 'Generated: ${_fmtDateTime(DateTime.now())}',
      offset: Offset(pageInset + cardInset, y),
      style: footerStyle,
      maxWidth: contentWidth,
      maxLines: 1,
    );

    final image = await recorder.endRecording().toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Unable to render receipt image.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _downloadReceipt({
    required int orderId,
    required int storeId,
    required String reference,
    required String paymentStatus,
    required DateTime? createdAt,
    required double subtotal,
    required double discount,
    required double total,
    required List<Map<String, dynamic>> items,
    required Map<int, Map<String, dynamic>> menuById,
    required Map<int, List<_OrderAddonDto>> addonsByOrderItemId,
    required _VoucherDetails? voucherDetails,
  }) async {
    try {
      final storeName = await _resolveStoreName(storeId);
      final receiptItems = <_ReceiptLineItem>[];
      for (final it in items) {
        final menuId = (it['menu_id'] as num?)?.toInt();
        final orderItemId = (it['order_item_id'] as num?)?.toInt();
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        final unitPrice = (it['unit_price'] as num?)?.toDouble() ?? 0;
        final isFree = it['is_free_item'] == true;
        final itemName =
            (menuId != null ? (menuById[menuId]?['name'] ?? 'Item') : 'Item')
                .toString();
        final addons = orderItemId == null
            ? const <_OrderAddonDto>[]
            : (addonsByOrderItemId[orderItemId] ?? const <_OrderAddonDto>[]);
        receiptItems.add(
          _ReceiptLineItem(
            name: itemName,
            qty: qty,
            unitPrice: unitPrice,
            lineTotal: isFree ? 0.0 : (unitPrice * qty),
            isFree: isFree,
            addons: addons,
          ),
        );
      }

      final baseName = reference.trim().isEmpty
          ? 'order_$orderId'
          : _sanitizeFileSegment(reference);
      final fileName = 'receipt_$baseName.png';
      final receiptPng = await _buildReceiptPngBytes(
        orderId: orderId,
        reference: reference,
        storeName: storeName,
        paymentStatus: paymentStatus,
        createdAt: createdAt,
        subtotal: subtotal,
        discount: discount,
        total: total,
        lineItems: receiptItems,
        voucherDetails: voucherDetails,
      );

      if (Platform.isAndroid) {
        try {
          final savedUri = await _mediaStoreChannel.invokeMethod<String>(
            'saveImageToGallery',
            <String, dynamic>{'name': fileName, 'bytes': receiptPng},
          );
          if ((savedUri ?? '').trim().isNotEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Receipt image saved to Photos.')),
            );
            return;
          }
        } catch (_) {
          // Fall through to direct file save fallback.
        }
      }

      final candidateDirs = <Directory>[];
      if (Platform.isAndroid) {
        candidateDirs.add(Directory('/storage/emulated/0/Pictures/Siply'));
        candidateDirs.add(Directory('/storage/emulated/0/DCIM/Siply'));
        candidateDirs.add(Directory('/storage/emulated/0/Download'));
      }
      candidateDirs.add(await getApplicationDocumentsDirectory());

      File? savedFile;
      for (final dir in candidateDirs) {
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final target = File('${dir.path}/$fileName');
          await target.writeAsBytes(receiptPng, flush: true);
          savedFile = target;
          break;
        } catch (_) {
          // Try next writable directory.
        }
      }

      if (savedFile == null) {
        throw Exception('No writable location found for receipt.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Receipt image saved: ${savedFile.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save receipt: $e')));
    }
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
  }

  Future<bool> _hasReviewForOrder(int orderId) async {
    try {
      final row = await _client
          .from('store_order_reviews')
          .select('review_id')
          .eq('order_id', orderId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openReviewSheet({
    required int orderId,
    required int storeId,
    required int userId,
  }) async {
    if (!mounted) return;
    int service = 0;
    int drink = 0;
    final notesCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget stars({
              required int value,
              required ValueChanged<int> onChanged,
            }) {
              return Row(
                children: List.generate(5, (i) {
                  final idx = i + 1;
                  return IconButton(
                    onPressed: _submittingReview ? null : () => onChanged(idx),
                    icon: Icon(
                      idx <= value
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber,
                    ),
                  );
                }),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rate Your Order',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Service (1-5)'),
                    stars(
                      value: service,
                      onChanged: (v) => setModalState(() => service = v),
                    ),
                    const Text('Drink (1-5)'),
                    stars(
                      value: drink,
                      onChanged: (v) => setModalState(() => drink = v),
                    ),
                    TextField(
                      controller: notesCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submittingReview || service < 1 || drink < 1
                            ? null
                            : () async {
                                setState(() => _submittingReview = true);
                                try {
                                  await _client
                                      .from('store_order_reviews')
                                      .upsert({
                                        'order_id': orderId,
                                        'store_id': storeId,
                                        'user_id': userId,
                                        'service_rating': service,
                                        'drink_rating': drink,
                                        'notes': notesCtrl.text.trim().isEmpty
                                            ? null
                                            : notesCtrl.text.trim(),
                                      }, onConflict: 'order_id');
                                  await _client
                                      .from('orders')
                                      .update({'status': 'reviewed'})
                                      .eq('order_id', orderId);
                                  if (mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Review failed: $e'),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _submittingReview = false);
                                  }
                                }
                              },
                        child: Text(
                          _submittingReview ? 'Submitting...' : 'Submit Review',
                        ),
                      ),
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

  Future<int?> _getOrCreateActiveCartId(int storeId) async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return null;

    final rows = await _client
        .from('carts')
        .select('cart_id')
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .eq('status', 'active')
        .limit(1);

    if ((rows as List).isNotEmpty) {
      return ((rows.first as Map)['cart_id'] as num).toInt();
    }

    final created = await _client
        .from('carts')
        .insert({'user_id': userId, 'store_id': storeId, 'status': 'active'})
        .select('cart_id')
        .single();
    return (created['cart_id'] as num).toInt();
  }

  Future<void> _addOrderItemsToCart({
    required int storeId,
    required List<Map<String, dynamic>> items,
    required Map<int, Map<String, dynamic>> menuById,
    required Map<int, List<_OrderAddonDto>> addonsByOrderItemId,
  }) async {
    final cartId = await _getOrCreateActiveCartId(storeId);
    if (cartId == null) return;

    for (final it in items) {
      final orderItemId = (it['order_item_id'] as num).toInt();
      final menuId = (it['menu_id'] as num).toInt();
      final qty = (it['quantity'] as num?)?.toInt() ?? 0;
      if (qty <= 0) continue;

      final menu = menuById[menuId];
      final price =
          (menu?['price'] as num?)?.toDouble() ??
          (it['unit_price'] as num?)?.toDouble() ??
          0;

      final existing = await _client
          .from('cart_items')
          .select('cart_item_id, quantity')
          .eq('cart_id', cartId)
          .eq('menu_id', menuId)
          .isFilter('variant_id', null)
          .maybeSingle();

      int cartItemId;
      if (existing == null) {
        final created = await _client
            .from('cart_items')
            .insert({
              'cart_id': cartId,
              'store_id': storeId,
              'menu_id': menuId,
              'variant_id': null,
              'quantity': qty,
              'price': price,
            })
            .select('cart_item_id')
            .single();
        cartItemId = (created['cart_item_id'] as num).toInt();
      } else {
        cartItemId = (existing['cart_item_id'] as num).toInt();
        final nextQty = ((existing['quantity'] as num?)?.toInt() ?? 0) + qty;
        await _client
            .from('cart_items')
            .update({'quantity': nextQty, 'price': price})
            .eq('cart_item_id', cartItemId);
      }

      final addons =
          addonsByOrderItemId[orderItemId] ?? const <_OrderAddonDto>[];
      if (addons.isEmpty) continue;

      for (final addon in addons) {
        final addonExisting = await _client
            .from('cart_item_addons')
            .select('cart_item_addon_id, quantity')
            .eq('cart_item_id', cartItemId)
            .eq('addon_menu_id', addon.menuId)
            .maybeSingle();

        if (addonExisting == null) {
          await _client.from('cart_item_addons').insert({
            'cart_item_id': cartItemId,
            'addon_menu_id': addon.menuId,
            'quantity': addon.qty,
            'unit_price': addon.unitPrice,
            'line_subtotal': addon.unitPrice * addon.qty,
          });
        } else {
          final nextQty =
              ((addonExisting['quantity'] as num?)?.toInt() ?? 0) + addon.qty;
          await _client
              .from('cart_item_addons')
              .update({
                'quantity': nextQty,
                'unit_price': addon.unitPrice,
                'line_subtotal': addon.unitPrice * nextQty,
              })
              .eq(
                'cart_item_addon_id',
                (addonExisting['cart_item_addon_id'] as num).toInt(),
              );
        }
      }
    }
  }

  Future<void> _showOrderAgainModal({
    required int storeId,
    required List<Map<String, dynamic>> items,
    required Map<int, Map<String, dynamic>> menuById,
    required Map<int, List<_OrderAddonDto>> addonsByOrderItemId,
  }) async {
    if (!mounted) return;
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
                ...items.map((it) {
                  final orderItemId = (it['order_item_id'] as num).toInt();
                  final menuId = (it['menu_id'] as num).toInt();
                  final qty = (it['quantity'] as num?)?.toInt() ?? 0;
                  final name = (menuById[menuId]?['name'] ?? 'Item').toString();
                  final addons =
                      addonsByOrderItemId[orderItemId] ??
                      const <_OrderAddonDto>[];
                  final addonsLabel = addons.isEmpty
                      ? ''
                      : ' • Add-ons: ${addons.map((a) => '${a.name} x${a.qty}').join(', ')}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('$name x$qty$addonsLabel'),
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
                          await _addOrderItemsToCart(
                            storeId: storeId,
                            items: items,
                            menuById: menuById,
                            addonsByOrderItemId: addonsByOrderItemId,
                          );
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

  Future<void> _promptReviewIfNeeded(Map<String, dynamic> order) async {
    final orderId = (order['order_id'] as num?)?.toInt();
    if (orderId == null) return;
    final status = (order['status'] ?? '').toString();
    if (status != 'completed') return;
    if (_reviewPromptedOrderIds.contains(orderId)) return;

    _reviewPromptedOrderIds.add(orderId);

    final alreadyReviewed = await _hasReviewForOrder(orderId);
    if (alreadyReviewed) {
      await _client
          .from('orders')
          .update({'status': 'reviewed'})
          .eq('order_id', orderId);
      return;
    }

    final storeId = (order['store_id'] as num?)?.toInt();
    final userId = (order['user_id'] as num?)?.toInt();
    if (storeId == null || userId == null) return;

    if (!mounted) return;
    await _openReviewSheet(orderId: orderId, storeId: storeId, userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    final orderId = _orderId;

    return WillPopScope(
      onWillPop: () async {
        _goHome();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7FB),
        appBar: AppBar(
          backgroundColor: AppTheme.primary,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goHome,
          ),
          title: const Text(
            'Order Details',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: orderId == null
              ? const Center(
                  child: Text(
                    'Missing orderId.\nPass arguments: { "orderId": <int> }',
                    textAlign: TextAlign.center,
                  ),
                )
              : StreamBuilder<List<Map<String, dynamic>>>(
                  // Live stream for the order row
                  stream: _client
                      .from('orders')
                      .stream(primaryKey: ['order_id'])
                      .eq('order_id', orderId),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Error loading order:\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red[800]),
                          ),
                        ),
                      );
                    }

                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final rows = snap.data!;
                    if (rows.isEmpty) {
                      return const Center(child: Text('Order not found.'));
                    }

                    final order = rows.first;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _promptReviewIfNeeded(order);
                    });

                    final status = (order['status'] ?? 'pending_payment')
                        .toString();
                    final paymentStatus = (order['payment_status'] ?? 'unpaid')
                        .toString();

                    final reference = (order['reference_number'] ?? '')
                        .toString();
                    final subtotal =
                        (order['subtotal'] as num?)?.toDouble() ?? 0.0;
                    final discount =
                        (order['discount_amount'] as num?)?.toDouble() ?? 0.0;
                    final total =
                        (order['total_amount'] as num?)?.toDouble() ?? 0.0;

                    final createdAt = _parseTs(order['created_at']);
                    final paidAt = _parseTs(order['paid_at']);

                    final payProvider =
                        (order['payment_provider'] ?? 'paymongo').toString();
                    final payMethod = (order['payment_method'] ?? '')
                        .toString();

                    final currentStep = _stepFromStatus(status);

                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TOP STATUS CARD
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 22,
                                horizontal: 18,
                              ),
                              margin: const EdgeInsets.only(bottom: 18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.06),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'ORDER STATUS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black54,
                                      fontSize: 12,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // show reference instead of dummy pickup number
                                  Text(
                                    reference.isEmpty
                                        ? 'ORDER #$orderId'
                                        : reference,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // payment status pill
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _paymentStatusColor(
                                        paymentStatus,
                                      ).withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _paymentStatusColor(
                                          paymentStatus,
                                        ).withOpacity(0.35),
                                      ),
                                    ),
                                    child: Text(
                                      'Payment: ${_prettyPaymentStatus(paymentStatus)}'
                                      '${paidAt != null ? ' • ${_fmtDateTime(paidAt)}' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: _paymentStatusColor(
                                          paymentStatus,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),
                                  OrderStatusStep(currentStep: currentStep),
                                  const SizedBox(height: 12),

                                  // Removed redundant status text below stepper
                                ],
                              ),
                            ),

                            // STORE CARD (fetch store name)
                            FutureBuilder<Map<String, dynamic>?>(
                              future: _client
                                  .from('stores')
                                  .select('store_id, store_name')
                                  .eq('store_id', order['store_id'])
                                  .maybeSingle(),
                              builder: (context, storeSnap) {
                                final store = storeSnap.data;
                                final fallbackLabel =
                                    'Store #${(order['store_id'] as num?)?.toInt() ?? ''}';
                                final rawStoreName =
                                    (store?['store_name'] ?? '')
                                        .toString()
                                        .trim();
                                final storeName = rawStoreName.isEmpty
                                    ? fallbackLabel
                                    : rawStoreName;

                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.store,
                                        color: Colors.black54,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          storeName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                            // ITEMS (live)
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _client
                                  .from('order_items')
                                  .stream(primaryKey: ['order_item_id'])
                                  .eq('order_id', orderId),
                              builder: (context, itemsSnap) {
                                if (itemsSnap.hasError) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                      'Error loading items: ${itemsSnap.error}',
                                      style: TextStyle(color: Colors.red[800]),
                                    ),
                                  );
                                }

                                final items = itemsSnap.data ?? const [];

                                // If you want names/images, fetch store_menu_items for all menu_ids
                                return FutureBuilder<_OrderItemsContext>(
                                  future: _buildOrderItemsContext(
                                    items,
                                    (order['voucher_id'] as num?)?.toInt(),
                                  ),
                                  builder: (context, ctxSnap) {
                                    if (!ctxSnap.hasData) {
                                      return const SizedBox.shrink();
                                    }
                                    final ctx = ctxSnap.data!;
                                    final menuById = ctx.menuById;
                                    final addonsByOrderItemId =
                                        ctx.addonsByOrderItemId;
                                    final categoryByMenuId =
                                        ctx.categoryByMenuId;
                                    final voucherDetails = ctx.voucherDetails;
                                    final canOrderAgain =
                                        status == 'completed' ||
                                        status == 'reviewed';

                                    // Build cards
                                    final itemCards = items.map((it) {
                                      final menuId = (it['menu_id'] as num)
                                          .toInt();
                                      final orderItemId =
                                          (it['order_item_id'] as num).toInt();
                                      final qty =
                                          (it['quantity'] as num?)?.toInt() ??
                                          1;
                                      final unit =
                                          (it['unit_price'] as num?)
                                              ?.toDouble() ??
                                          0.0;
                                      final isFree =
                                          (it['is_free_item'] == true);

                                      final menu = menuById[menuId];
                                      final name = (menu?['name'] ?? 'Item')
                                          .toString();

                                      final rawImg = (menu?['image_url'] ?? '')
                                          .toString();
                                      final img = _menuImageUrl(rawImg);
                                      final addons =
                                          addonsByOrderItemId[orderItemId] ??
                                          const <_OrderAddonDto>[];
                                      final addonsLabel = addons.isEmpty
                                          ? null
                                          : addons
                                                .map(
                                                  (a) => '${a.name} x${a.qty}',
                                                )
                                                .join(', ');
                                      final addonsUnitTotal = addons
                                          .fold<double>(
                                            0.0,
                                            (sum, a) =>
                                                sum + (a.unitPrice * a.qty),
                                          );
                                      final categoryId =
                                          categoryByMenuId[menuId];
                                      final voucherEligible =
                                          voucherDetails == null
                                          ? false
                                          : _isOrderItemEligibleForVoucher(
                                              voucherDetails,
                                              menuId,
                                              categoryId,
                                            );

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.04,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Container(
                                                width: 52,
                                                height: 52,
                                                color: Colors.grey[200],
                                                child:
                                                    (img ?? '').trim().isEmpty
                                                    ? Icon(
                                                        Icons
                                                            .local_cafe_outlined,
                                                        color: AppTheme.primary
                                                            .withOpacity(0.6),
                                                      )
                                                    : Image.network(
                                                        img!,
                                                        width: 52,
                                                        height: 52,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              _,
                                                              __,
                                                              ___,
                                                            ) => Icon(
                                                              Icons
                                                                  .local_cafe_outlined,
                                                              color: AppTheme
                                                                  .primary
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                            ),
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                fontSize: 14.5,
                                                              ),
                                                        ),
                                                      ),
                                                      if (isFree)
                                                        Container(
                                                          margin:
                                                              const EdgeInsets.only(
                                                                left: 8,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors.green
                                                                .withOpacity(
                                                                  0.10,
                                                                ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  999,
                                                                ),
                                                            border: Border.all(
                                                              color: Colors
                                                                  .green
                                                                  .withOpacity(
                                                                    0.35,
                                                                  ),
                                                            ),
                                                          ),
                                                          child: const Text(
                                                            'FREE',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              fontSize: 11,
                                                              color:
                                                                  Colors.green,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    isFree
                                                        ? '₱0.00 x $qty'
                                                        : '₱${unit.toStringAsFixed(2)} x $qty',
                                                    style: TextStyle(
                                                      color: Colors.grey[700],
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  if (addonsLabel != null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Add-ons: $addonsLabel • +₱${addonsUnitTotal.toStringAsFixed(2)}',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                  if (voucherEligible) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Voucher applied: ${voucherDetails.code}',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: AppTheme.primary,
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  isFree
                                                      ? '₱0.00'
                                                      : '₱${(unit * qty).toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: AppTheme.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList();

                                    final itemCount = items.fold<int>(
                                      0,
                                      (sum, it) =>
                                          sum +
                                          ((it['quantity'] as num?)?.toInt() ??
                                              0),
                                    );

                                    return Column(
                                      children: [
                                        ...itemCards,
                                        if (canOrderAgain)
                                          Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(
                                              bottom: 10,
                                              top: 2,
                                            ),
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                _showOrderAgainModal(
                                                  storeId:
                                                      (order['store_id'] as num)
                                                          .toInt(),
                                                  items: items,
                                                  menuById: menuById,
                                                  addonsByOrderItemId:
                                                      addonsByOrderItemId,
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                              label: const Text('Order Again'),
                                            ),
                                          ),

                                        if (voucherDetails != null)
                                          Container(
                                            width: double.infinity,
                                            margin: const EdgeInsets.only(
                                              top: 8,
                                              bottom: 10,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                              horizontal: 18,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.04),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                              border: Border.all(
                                                color: Colors.amber.withOpacity(
                                                  0.25,
                                                ),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.percent,
                                                      color: Colors.amber,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    const Text(
                                                      'Voucher',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        voucherDetails.title
                                                                .trim()
                                                                .isEmpty
                                                            ? voucherDetails
                                                                  .code
                                                            : '${voucherDetails.title} (${voucherDetails.code})',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.red,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Applies to: ${_voucherTargetsLabel(voucherDetails)}',
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.grey[700],
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        // TOTALS CARD
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                            horizontal: 18,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.04,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              _kvRow(
                                                'Subtotal',
                                                '₱${subtotal.toStringAsFixed(2)}',
                                              ),
                                              const SizedBox(height: 8),
                                              _kvRow(
                                                'Discount',
                                                discount > 0
                                                    ? '-₱${discount.toStringAsFixed(2)}'
                                                    : '₱0.00',
                                                valueColor: discount > 0
                                                    ? Colors.green[700]
                                                    : Colors.black87,
                                              ),
                                              const SizedBox(height: 10),
                                              const Divider(height: 12),
                                              const SizedBox(height: 10),
                                              _kvRow(
                                                'Total',
                                                '₱${total.toStringAsFixed(2)}',
                                                valueColor: AppTheme.primary,
                                                isStrong: true,
                                              ),
                                            ],
                                          ),
                                        ),

                                        // PAYMENT SUMMARY CARD
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                            horizontal: 18,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.04,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '$itemCount item(s)',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${payProvider.toUpperCase()}${payMethod.isEmpty ? '' : ' • ${payMethod.toUpperCase()}'}',
                                                      style: const TextStyle(
                                                        color: Colors.grey,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _paymentStatusColor(
                                                    paymentStatus,
                                                  ).withOpacity(0.10),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: _paymentStatusColor(
                                                      paymentStatus,
                                                    ).withOpacity(0.35),
                                                  ),
                                                ),
                                                child: Text(
                                                  _prettyPaymentStatus(
                                                    paymentStatus,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: _paymentStatusColor(
                                                      paymentStatus,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // ORDER INFO CARD
                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                            horizontal: 18,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.04,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            children: [
                                              _kvRow(
                                                'Order Time',
                                                _fmtDateTime(createdAt),
                                              ),
                                              const SizedBox(height: 10),
                                              _kvRow(
                                                'Order ID',
                                                orderId.toString(),
                                              ),
                                              const SizedBox(height: 10),
                                              _kvRow(
                                                'Reference',
                                                reference.isEmpty
                                                    ? '—'
                                                    : reference,
                                              ),
                                            ],
                                          ),
                                        ),

                                        Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: OutlinedButton.icon(
                                            onPressed: () {
                                              final storeId =
                                                  (order['store_id'] as num?)
                                                      ?.toInt();
                                              if (storeId == null) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Unable to find store for this order.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              _downloadReceipt(
                                                orderId: orderId,
                                                storeId: storeId,
                                                reference: reference,
                                                paymentStatus: paymentStatus,
                                                createdAt: createdAt,
                                                subtotal: subtotal,
                                                discount: discount,
                                                total: total,
                                                items: items,
                                                menuById: menuById,
                                                addonsByOrderItemId:
                                                    addonsByOrderItemId,
                                                voucherDetails: voucherDetails,
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.download_rounded,
                                            ),
                                            label: const Text(
                                              'Download Receipt',
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchMenuDetailsForOrderItems(
    List<Map<String, dynamic>> items,
  ) async {
    if (items.isEmpty) return const [];

    final ids = items
        .map((e) => (e['menu_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet()
        .toList();

    if (ids.isEmpty) return const [];

    // NOTE: adjust selected fields based on your store_menu_items schema
    final rows = await _client
        .from('store_menu_items')
        .select('menu_id, name, image_url, price, category_id')
        .inFilter('menu_id', ids);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Widget _kvRow(
    String key,
    String value, {
    Color? valueColor,
    bool isStrong = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(
            key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isStrong ? FontWeight.w900 : FontWeight.w800,
              color: valueColor ?? Colors.black87,
              fontSize: isStrong ? 15 : 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptLineItem {
  final String name;
  final int qty;
  final double unitPrice;
  final double lineTotal;
  final bool isFree;
  final List<_OrderAddonDto> addons;

  const _ReceiptLineItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    required this.isFree,
    required this.addons,
  });
}

class _OrderAddonDto {
  final int menuId;
  final String name;
  final int qty;
  final double unitPrice;

  const _OrderAddonDto({
    required this.menuId,
    required this.name,
    required this.qty,
    required this.unitPrice,
  });
}

class _OrderItemsContext {
  final Map<int, Map<String, dynamic>> menuById;
  final Map<int, List<_OrderAddonDto>> addonsByOrderItemId;
  final Map<int, int?> categoryByMenuId;
  final _VoucherDetails? voucherDetails;

  const _OrderItemsContext({
    required this.menuById,
    required this.addonsByOrderItemId,
    required this.categoryByMenuId,
    required this.voucherDetails,
  });
}

class _VoucherTarget {
  final String targetType;
  final int? categoryId;
  final int? menuId;

  const _VoucherTarget({
    required this.targetType,
    this.categoryId,
    this.menuId,
  });

  factory _VoucherTarget.fromMap(Map<String, dynamic> m) => _VoucherTarget(
    targetType: (m['target_type'] ?? '').toString(),
    categoryId: (m['category_id'] as num?)?.toInt(),
    menuId: (m['menu_id'] as num?)?.toInt(),
  );
}

class _BogoRule {
  final int ruleId;
  final String buyType;
  final int? buyMenuId;
  final int? buyCategoryId;
  final int buyQty;
  final String getType;
  final int? getMenuId;
  final int? getCategoryId;
  final int getQty;
  final double getDiscountPercent;

  const _BogoRule({
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

  factory _BogoRule.fromMap(Map<String, dynamic> m) => _BogoRule(
    ruleId: (m['rule_id'] as num).toInt(),
    buyType: (m['buy_type'] ?? '').toString(),
    buyMenuId: (m['buy_menu_id'] as num?)?.toInt(),
    buyCategoryId: (m['buy_category_id'] as num?)?.toInt(),
    buyQty: (m['buy_qty'] as num?)?.toInt() ?? 1,
    getType: (m['get_type'] ?? '').toString(),
    getMenuId: (m['get_menu_id'] as num?)?.toInt(),
    getCategoryId: (m['get_category_id'] as num?)?.toInt(),
    getQty: (m['get_qty'] as num?)?.toInt() ?? 1,
    getDiscountPercent: (m['get_discount_percent'] as num?)?.toDouble() ?? 100,
  );
}

class _VoucherDetails {
  final int voucherId;
  final String code;
  final String title;
  final String voucherType;
  final int? buyMenuId;
  final int? freeMenuId;
  final List<_VoucherTarget> targets;
  final List<_BogoRule> bogoRules;
  final Map<int, String> menuNameById;
  final Map<int, String> categoryNameById;

  const _VoucherDetails({
    required this.voucherId,
    required this.code,
    required this.title,
    required this.voucherType,
    required this.buyMenuId,
    required this.freeMenuId,
    required this.targets,
    required this.bogoRules,
    required this.menuNameById,
    required this.categoryNameById,
  });
}
