import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushTokenService.showBackgroundNotification(message);
}

class PushTokenService {
  final SupabaseClient _client;
  PushTokenService(this._client);

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localInitDone = false;
  static bool _listenersBound = false;
  static RealtimeChannel? _orderStatusChannel;
  static int? _orderStatusUserId;
  static final Set<String> _sentNotificationKeys = <String>{};

  Future<void> initAndSyncToken() async {
    final messaging = FirebaseMessaging.instance;

    await Permission.notification.request();
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _initLocalNotifications();

    final token = await messaging.getToken();
    if (token != null) {
      await _upsertToken(token);
    }

    if (!_listenersBound) {
      _listenersBound = true;

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _upsertToken(newToken);
      });

      FirebaseMessaging.onMessage.listen((message) async {
        await _showLocalNotification(message);
      });
    }

    final userId = await _resolveCustomerUserId();
    if (userId != null) {
      await _ensureOrderStatusRealtime(userId);
    }
  }

  Future<int?> _resolveCustomerUserId() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final row = await _client
        .from('users')
        .select('user_id')
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .maybeSingle();

    return (row?['user_id'] as num?)?.toInt();
  }

  Future<void> _ensureOrderStatusRealtime(int userId) async {
    if (_orderStatusChannel != null && _orderStatusUserId == userId) {
      return;
    }

    if (_orderStatusChannel != null) {
      try {
        await _client.removeChannel(_orderStatusChannel!);
      } catch (_) {}
      _orderStatusChannel = null;
      _orderStatusUserId = null;
      _sentNotificationKeys.clear();
    }

    final channel = _client.channel('orders-status-$userId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        unawaited(_handleRealtimeOrderStatus(payload));
      },
    );
    channel.subscribe();

    _orderStatusChannel = channel;
    _orderStatusUserId = userId;
  }

  Future<void> _handleRealtimeOrderStatus(PostgresChangePayload payload) async {
    final orderId = (payload.newRecord['order_id'] as num?)?.toInt();
    if (orderId == null) return;

    final newStatus = (payload.newRecord['status'] ?? '').toString().trim();
    final oldStatus = (payload.oldRecord['status'] ?? '').toString().trim();
    final newPaymentStatus = (payload.newRecord['payment_status'] ?? '')
        .toString()
        .trim();
    final oldPaymentStatus = (payload.oldRecord['payment_status'] ?? '')
        .toString()
        .trim();
    final totalAmount = _toDouble(payload.newRecord['total_amount']);

    final draft = _buildNotificationFromOrderUpdate(
      newStatus: newStatus,
      oldStatus: oldStatus,
      newPaymentStatus: newPaymentStatus,
      oldPaymentStatus: oldPaymentStatus,
      totalAmount: totalAmount,
    );
    if (draft == null) return;

    await _showLocalNotificationText(
      title: draft.title,
      body: draft.body,
      payload: jsonEncode({
        'order_id': orderId,
        'status': newStatus,
        'payment_status': newPaymentStatus,
        'notification_type': draft.type,
      }),
      dedupeKey: '$orderId:${draft.type}',
    );
  }

  static _OrderNotificationDraft? _buildNotificationFromOrderUpdate({
    required String newStatus,
    required String oldStatus,
    required String newPaymentStatus,
    required String oldPaymentStatus,
    required double? totalAmount,
  }) {
    final normalizedNewStatus = newStatus.toLowerCase();
    final normalizedOldStatus = oldStatus.toLowerCase();
    final normalizedNewPayment = newPaymentStatus.toLowerCase();
    final normalizedOldPayment = oldPaymentStatus.toLowerCase();

    if (normalizedNewStatus != normalizedOldStatus) {
      final draft = _notificationFromStatus(normalizedNewStatus, totalAmount);
      if (draft != null) return draft;
    }

    // Some realtime updates may not include old values. Avoid inferring paid
    // repeatedly from incomplete oldRecord snapshots.
    if (normalizedOldPayment.isNotEmpty &&
        normalizedOldPayment != 'paid' &&
        normalizedNewPayment == 'paid') {
      return _paidNotification(totalAmount);
    }

    return null;
  }

  Future<void> _upsertToken(String token) async {
    final userId = await _resolveCustomerUserId();
    if (userId == null) return;

    await _client.from('user_push_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': 'mobile',
      'is_active': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }

  static Future<void> _initLocalNotifications() async {
    if (_localInitDone) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOSInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iOSInit,
    );
    await _localNotifications.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      'orders',
      'Order updates',
      description: 'Notifications about your order status',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _localInitDone = true;
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final orderId = int.tryParse((message.data['order_id'] ?? '').toString());
    final draft = _buildNotificationFromRemoteMessage(message);
    if (draft == null) return;

    await _showLocalNotificationText(
      title: draft.title,
      body: draft.body,
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
      dedupeKey: orderId == null ? null : '$orderId:${draft.type}',
    );
  }

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    final orderId = int.tryParse((message.data['order_id'] ?? '').toString());
    final draft = _buildNotificationFromRemoteMessage(message);
    if (draft == null) return;

    await _showLocalNotificationText(
      title: draft.title,
      body: draft.body,
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
      dedupeKey: orderId == null ? null : '$orderId:${draft.type}',
    );
  }

  static _OrderNotificationDraft? _buildNotificationFromRemoteMessage(
    RemoteMessage message,
  ) {
    final event = (message.data['event'] ?? '').toString().trim().toLowerCase();
    final status = (message.data['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final paymentStatus = (message.data['payment_status'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final totalAmount = _toDouble(message.data['total_amount']);

    // Only explicit payment events should produce the paid notification.
    if (event == 'payment_success') {
      return _paidNotification(totalAmount);
    }

    if (event == 'order_preparing') {
      return _notificationFromStatus('preparing', totalAmount);
    }

    if (event == 'order_ready') {
      return _notificationFromStatus('ready_for_pickup', totalAmount);
    }

    if (event == 'order_status_changed' || event == 'order_confirmed') {
      return _notificationFromStatus(status, totalAmount);
    }

    final statusDraft = _notificationFromStatus(status, totalAmount);
    if (statusDraft != null) return statusDraft;

    // Backward compatibility: allow paid fallback only for legacy payloads
    // that don't provide an explicit event/status.
    if (event.isEmpty && status.isEmpty && paymentStatus == 'paid') {
      return _paidNotification(totalAmount);
    }

    return null;
  }

  static _OrderNotificationDraft? _notificationFromStatus(
    String status,
    double? totalAmount,
  ) {
    switch (status) {
      case 'preparing':
        return const _OrderNotificationDraft(
          type: 'preparing',
          title: 'Your Order is being Prepared',
          body: 'Your Order is being Prepared',
        );
      case 'ready_for_pickup':
        return const _OrderNotificationDraft(
          type: 'ready',
          title: 'Your Order is ready for claiming.',
          body: 'Your Order is ready for claiming.',
        );
      case 'completed':
        return const _OrderNotificationDraft(
          type: 'completed',
          title: 'Your Order is Complete! Please Leave a Review!!',
          body: 'Your Order is Complete! Please Leave a Review!!',
        );
      case 'paid':
        return _paidNotification(totalAmount);
      default:
        return null;
    }
  }

  static _OrderNotificationDraft _paidNotification(double? totalAmount) {
    return _OrderNotificationDraft(
      type: 'paid',
      title: 'Your Order has been Paid',
      body:
          'Your Order has been Paid and P ${_formatAmount(totalAmount)} is spent.',
    );
  }

  static String _formatAmount(double? value) {
    final amount = value == null || value.isNaN || value.isInfinite
        ? 0.0
        : value;
    return amount.toStringAsFixed(2);
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static Future<void> _showLocalNotificationText({
    required String title,
    required String body,
    String? payload,
    String? dedupeKey,
  }) async {
    if (dedupeKey != null && dedupeKey.trim().isNotEmpty) {
      if (_sentNotificationKeys.contains(dedupeKey)) return;
      _sentNotificationKeys.add(dedupeKey);
      if (_sentNotificationKeys.length > 400) {
        _sentNotificationKeys.clear();
      }
    }

    await _initLocalNotifications();

    ByteArrayAndroidBitmap? largeIcon;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      largeIcon = ByteArrayAndroidBitmap(bytes.buffer.asUint8List());
    } catch (_) {
      // Ignore if asset fails to load.
    }

    final androidDetails = AndroidNotificationDetails(
      'orders',
      'Order updates',
      channelDescription: 'Notifications about your order status',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      largeIcon: largeIcon,
    );
    const iOSDetails = DarwinNotificationDetails();
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload ?? '',
    );
  }
}

class _OrderNotificationDraft {
  final String type;
  final String title;
  final String body;

  const _OrderNotificationDraft({
    required this.type,
    required this.title,
    required this.body,
  });
}
