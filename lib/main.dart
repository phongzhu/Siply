import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

import 'services/push_token_service.dart';
import 'utils/app_theme.dart';

import 'screens/animated_splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/main_shell.dart';
import 'screens/view_store_screen.dart';
import 'screens/order_status_screen.dart';
import 'screens/paymongo_checkout_screen.dart';
import 'screens/auth/customer_otp_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/search_screen.dart';
import 'screens/profile_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ REQUIRED for Windows/Desktop
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://wzvlxfzhyudkoedllyha.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind6dmx4ZnpoeXVka29lZGxseWhhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgyMjI0MzAsImV4cCI6MjA4Mzc5ODQzMH0.1uQDftqPMlplakoNkXqfqEaLewLBVAUwjwAX469_GE4',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  debugPrint('Firebase + Supabase initialized');

  // 🔒 Only sync push tokens on MOBILE (Android / iOS)
  if (!Platform.isWindows) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final supa = Supabase.instance.client;
    supa.auth.onAuthStateChange.listen((_) async {
      final user = supa.auth.currentUser;
      if (user != null) {
        await PushTokenService(supa).initAndSyncToken();
      }
    });
  }

  runApp(const SiplyApp());
}

class SiplyApp extends StatelessWidget {
  const SiplyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Siply',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const AnimatedSplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/main': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is Map) {
            final map = args.cast<String, dynamic>();
            final tab = (map['tab'] as num?)?.toInt() ?? 0;
            return MainShell(initialIndex: tab);
          }
          return const MainShell();
        },

        CartScreen.route: (context) => const CartScreen(),
        OrderStatusScreen.route: (context) =>
            const OrderStatusScreen(), // ✅ Added
        PayMongoCheckoutScreen.route: (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is Map) {
            final map = args.cast<String, dynamic>();
            return PayMongoCheckoutScreen(
              orderId: (map['orderId'] as num).toInt(),
              checkoutUrl: (map['checkoutUrl'] ?? '').toString(),
              successUrl: (map['successUrl'] ?? '').toString(),
              cancelUrl: (map['cancelUrl'] ?? '').toString(),
            );
          }

          return const _RouteArgsMissingScreen(
            title: 'Missing PayMongo args',
            message:
                'PayMongoCheckoutScreen requires orderId, checkoutUrl, successUrl, cancelUrl.',
          );
        },

        ViewStoreScreen.route: (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          if (args is int) {
            return ViewStoreScreen(storeId: args);
          } else if (args is Map) {
            final map = args.cast<String, dynamic>();
            return ViewStoreScreen(storeId: (map['storeId'] as num).toInt());
          }

          return const _RouteArgsMissingScreen(
            title: 'Missing storeId',
            message: 'ViewStoreScreen requires a storeId.',
          );
        },

        CustomerOTPScreen.route: (context) {
          final args = (ModalRoute.of(context)!.settings.arguments as Map)
              .cast<String, dynamic>();

          return CustomerOTPScreen(
            email: args['email'],
            password: args['password'],
            firstName: args['firstName'],
            middleName: args['middleName'],
            lastName: args['lastName'],
            extensionName: args['extensionName'],
            contactNumber: args['contactNumber'],
          );
        },

        ProfileScreen.route: (context) => const ProfileScreen(),

        '/search': (context) => const SearchScreen(),
      },
    );
  }
}

class _RouteArgsMissingScreen extends StatelessWidget {
  final String title;
  final String message;
  const _RouteArgsMissingScreen({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(message)),
    );
  }
}
