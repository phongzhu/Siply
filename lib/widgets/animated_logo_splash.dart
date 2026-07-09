import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedLogoSplash extends StatefulWidget {
  final VoidCallback onFinish;
  const AnimatedLogoSplash({super.key, required this.onFinish});

  @override
  State<AnimatedLogoSplash> createState() => _AnimatedLogoSplashState();
}

class _AnimatedLogoSplashState extends State<AnimatedLogoSplash>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;

  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    // Main animation controller
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Pulse animation for the glow effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Subtle rotation for particles
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    // Scale animation with elastic effect
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    // Fade in animation
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Pulse animation
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Slide up animation
    _slideAnim = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _mainController.forward();
    Future.delayed(const Duration(milliseconds: 2800), widget.onFinish);
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E3A8A), // Deep blue
              const Color(0xFF2563EB), // Bright blue
              const Color(0xFF3B82F6), // Sky blue
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated background particles
            ...List.generate(20, (index) => _buildParticle(index, size)),

            // Gradient overlay for depth
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.8,
                    colors: [
                      Colors.white.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Main logo content
            Center(
              child: AnimatedBuilder(
                animation: _mainController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _slideAnim.value),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Animated glow container
                            AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (context, child) {
                                return Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withOpacity(
                                          0.3 * _pulseAnim.value,
                                        ),
                                        blurRadius: 60 * _pulseAnim.value,
                                        spreadRadius: 20 * _pulseAnim.value,
                                      ),
                                      BoxShadow(
                                        color: const Color(
                                          0xFF60A5FA,
                                        ).withOpacity(0.4),
                                        blurRadius: 40,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(32),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.15),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.3),
                                        width: 2,
                                      ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withOpacity(0.25),
                                            Colors.white.withOpacity(0.1),
                                          ],
                                        ),
                                      ),
                                      child: Image.asset(
                                        'assets/images/logo.png',
                                        width: size.width * 0.35,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 40),

                            // Loading indicator
                            FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _mainController,
                                curve: const Interval(
                                  0.4,
                                  0.8,
                                  curve: Curves.easeIn,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Animated dots
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(3, (index) {
                                      return AnimatedBuilder(
                                        animation: _mainController,
                                        builder: (context, child) {
                                          final delay = index * 0.15;
                                          final animValue =
                                              (_mainController.value - delay)
                                                  .clamp(0.0, 1.0);
                                          final scale =
                                              math.sin(
                                                    animValue * math.pi * 4,
                                                  ) *
                                                  0.3 +
                                              1.0;

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Transform.scale(
                                              scale: scale,
                                              child: Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Colors.white
                                                      .withOpacity(0.9),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.white
                                                          .withOpacity(0.5),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    }),
                                  ),
                                ],
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
  }

  Widget _buildParticle(int index, Size size) {
    final random = math.Random(index);
    final startX = random.nextDouble() * size.width;
    final startY = random.nextDouble() * size.height;
    final particleSize = random.nextDouble() * 4 + 2;
    final duration = random.nextInt(3000) + 2000;
    final delay = random.nextInt(1000);

    return AnimatedBuilder(
      animation: _rotateController,
      builder: (context, child) {
        final progress = (_rotateController.value + (delay / 1000)) % 1.0;
        final opacity = (math.sin(progress * math.pi) * 0.4 + 0.2).clamp(
          0.0,
          0.6,
        );

        return Positioned(
          left: startX + math.sin(progress * math.pi * 2) * 30,
          top: startY + math.cos(progress * math.pi * 2) * 30,
          child: Container(
            width: particleSize,
            height: particleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(opacity),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(opacity * 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
