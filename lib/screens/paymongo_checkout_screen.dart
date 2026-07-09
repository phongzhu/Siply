import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';
import 'order_status_screen.dart';

class PayMongoCheckoutScreen extends StatefulWidget {
  static const route = '/paymongo-checkout';

  final int orderId;
  final String checkoutUrl;
  final String successUrl;
  final String cancelUrl;

  const PayMongoCheckoutScreen({
    super.key,
    required this.orderId,
    required this.checkoutUrl,
    required this.successUrl,
    required this.cancelUrl,
  });

  @override
  State<PayMongoCheckoutScreen> createState() => _PayMongoCheckoutScreenState();
}

class _PayMongoCheckoutScreenState extends State<PayMongoCheckoutScreen> {
  WebViewController? _controller;
  bool _handledRedirect = false;
  bool _simulated = false;
  late final bool _isSupportedPlatform;
  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _isSupportedPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (_isSupportedPlatform) {
      _controller =
          WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..setBackgroundColor(Colors.white)
            ..setNavigationDelegate(
              NavigationDelegate(
                onNavigationRequest: (request) {
                  if (_handledRedirect) {
                    return NavigationDecision.navigate;
                  }

                  final url = request.url;
                  if (_isSimulate(url)) {
                    _handledRedirect = true;
                    _simulateAndGo();
                    return NavigationDecision.prevent;
                  }
                  if (_isSuccess(url)) {
                    _handledRedirect = true;
                    _goToStatus();
                    return NavigationDecision.prevent;
                  }
                  if (_isCancel(url)) {
                    _handledRedirect = true;
                    _handleCancel();
                    return NavigationDecision.prevent;
                  }
                  return NavigationDecision.navigate;
                },
                onPageFinished: (url) {
                  if (_handledRedirect) return;
                  _injectSimulateHook();
                  if (_isSuccess(url)) {
                    _handledRedirect = true;
                    _goToStatus();
                  }
                  if (_isCancel(url)) {
                    _handledRedirect = true;
                    _handleCancel();
                  }
                },
              ),
            )
            ..loadRequest(Uri.parse(widget.checkoutUrl));
    }
  }

  bool _isSuccess(String currentUrl) {
    return _matchesUrl(currentUrl, widget.successUrl);
  }

  bool _isCancel(String currentUrl) {
    return _matchesUrl(currentUrl, widget.cancelUrl);
  }

  bool _isSimulate(String currentUrl) {
    return currentUrl.startsWith('siply://simulate-payment');
  }

  bool _matchesUrl(String currentUrl, String targetUrl) {
    if (targetUrl.trim().isEmpty) return false;
    final current = Uri.tryParse(currentUrl);
    final target = Uri.tryParse(targetUrl);
    if (current == null || target == null) {
      return currentUrl.startsWith(targetUrl);
    }
    final currentBase = '${current.scheme}://${current.host}${current.path}';
    final targetBase = '${target.scheme}://${target.host}${target.path}';
    return currentBase == targetBase;
  }

  void _goToStatus() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      OrderStatusScreen.route,
      arguments: {'orderId': widget.orderId},
    );
  }

  Future<void> _simulateAndGo() async {
    if (_simulated) return;
    _simulated = true;
    try {
      await _client.from('orders').update({
        'payment_status': 'paid',
        'status': 'preparing',
        'paid_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('order_id', widget.orderId);
    } catch (_) {
      // no-op: fallback to status screen anyway
    }
    if (!mounted) return;
    _goToStatus();
  }

  void _injectSimulateHook() {
    if (_controller == null) return;
    _controller!.runJavaScript('''
      (function() {
        if (window.__siplySimHookAdded) return;
        window.__siplySimHookAdded = true;
        function attach() {
          const nodes = Array.from(document.querySelectorAll('button, a'));
          const btn = nodes.find(n => (n.innerText || '')
            .toLowerCase()
            .includes('download qr'));
          if (btn && !btn.__siplyHooked) {
            btn.__siplyHooked = true;
            btn.addEventListener('click', function() {
              window.location.href = 'siply://simulate-payment';
            });
          } else {
            setTimeout(attach, 800);
          }
        }
        attach();
      })();
    ''');
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/main', (route) => false);
  }

  void _handleCancel() {
    if (!mounted) return;
    _goHome();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment cancelled.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
        title: const Text(
          'Pay with QRPh',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isSupportedPlatform
            ? WebViewWidget(controller: _controller!)
            : Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.phone_android,
                      size: 56,
                      color: Colors.black54,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PayMongo checkout is only available on Android and iOS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Run this app on a mobile device to complete payment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _goHome,
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
