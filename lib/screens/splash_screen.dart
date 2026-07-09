import 'package:flutter/material.dart';
import '../widgets/primary_button.dart';
import 'home_screen.dart';

class SplashScreen extends StatelessWidget {
  static const route = '/';
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).size.width * 0.06; // responsive padding
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text(
                'Siply',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                'Queue-skip ordering for beverage shops.\nOrder & pay ahead, then claim fast.',
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Get Started',
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, HomeScreen.route),
              ),
              const SizedBox(height: 14),
              Text(
                'UI-only phase: no backend yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
