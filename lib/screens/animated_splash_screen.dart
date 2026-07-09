import 'package:flutter/material.dart';
import '../widgets/animated_logo_splash.dart';

class AnimatedSplashScreen extends StatelessWidget {
  static const route = '/splash';
  const AnimatedSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedLogoSplash(
      onFinish: () {
        Navigator.of(context).pushReplacementNamed('/login');
      },
    );
  }
}
