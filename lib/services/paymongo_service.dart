import 'package:supabase_flutter/supabase_flutter.dart';

class PayMongoCheckoutResult {
  final int orderId;
  final String checkoutSessionId;
  final String checkoutUrl;
  final String successUrl;
  final String cancelUrl;
  final bool reused;

  PayMongoCheckoutResult({
    required this.orderId,
    required this.checkoutSessionId,
    required this.checkoutUrl,
    required this.successUrl,
    required this.cancelUrl,
    required this.reused,
  });

  factory PayMongoCheckoutResult.fromMap(Map<String, dynamic> m) {
    return PayMongoCheckoutResult(
      orderId: (m['orderId'] as num).toInt(),
      checkoutSessionId: (m['checkoutSessionId'] ?? '').toString(),
      checkoutUrl: (m['checkoutUrl'] ?? '').toString(),
      successUrl: (m['successUrl'] ?? '').toString(),
      cancelUrl: (m['cancelUrl'] ?? '').toString(),
      reused: (m['reused'] as bool?) ?? false,
    );
  }
}

class PayMongoService {
  final SupabaseClient _client;

  PayMongoService(this._client);

  /// Calls Supabase Edge Function to create PayMongo checkout session
  Future<PayMongoCheckoutResult> createCheckoutSession({
    required int orderId,
  }) async {
    final res = await _client.functions.invoke(
      'create-paymongo-checkout',
      body: {'orderId': orderId},
    );

    if (res.status != 200) {
      throw Exception('Edge function error (${res.status}): ${res.data}');
    }

    final data = (res.data as Map).cast<String, dynamic>();
    final result = PayMongoCheckoutResult.fromMap(data);

    if (result.checkoutUrl.trim().isEmpty) {
      throw Exception('No checkoutUrl returned: $data');
    }

    return result;
  }
}
