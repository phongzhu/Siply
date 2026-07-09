import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _fadeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _ensureCustomerRole({
    required SupabaseClient client,
    required String uid,
    required String email,
  }) async {
    // Check if customer role already exists
    final customer = await client
        .from('users')
        .select('status')
        .eq('auth_user_id', uid)
        .eq('role', 'customer')
        .maybeSingle();

    if (customer != null) {
      final status = (customer['status'] as String?) ?? 'active';
      if (status != 'active') {
        throw Exception('Account is not active.');
      }
      return;
    }

    // If not, copy profile from ANY existing role row (store_owner/admin/staff)
    final anyRow = await client
        .from('users')
        .select(
          'first_name,middle_name,last_name,extension_name,contact_number,status',
        )
        .eq('auth_user_id', uid)
        .maybeSingle();

    // If even that doesn't exist, you must collect profile first
    if (anyRow == null) {
      throw Exception(
        'Profile not found. Please sign up first so we can create your customer profile.',
      );
    }

    final status = (anyRow['status'] as String?) ?? 'active';
    if (status != 'active') {
      throw Exception('Account is not active.');
    }

    // Create customer role row using same profile fields
    await client.from('users').upsert({
      'auth_user_id': uid,
      'role': 'customer',
      'user_email': email,
      'first_name': anyRow['first_name'],
      'middle_name': anyRow['middle_name'],
      'last_name': anyRow['last_name'],
      'extension_name': anyRow['extension_name'],
      'contact_number': anyRow['contact_number'],
      'status': 'active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'auth_user_id,role');
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState?.validate() != true) return;

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;

      // ✅ Auth login (real email)
      await client.auth.signInWithPassword(email: email, password: password);

      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Login failed: no current user.');
      }

      // ✅ Ensure customer role exists (if user came from store app, auto-create)
      await _ensureCustomerRole(client: client, uid: uid, email: email);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool? obscureText,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    final bool isObscure = obscureText ?? false;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isObscure,
        validator: validator,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey[400],
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.12),
                  AppTheme.primary.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(prefixIcon, color: AppTheme.primary, size: 20),
          ),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppTheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.withOpacity(0.04),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return ClipPath(
                  clipper: ImprovedTopWaveClipper(_waveController.value),
                  child: Container(
                    height: size.height * 0.28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.9),
                          const Color(0xFF60A5FA),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                    child: CustomPaint(
                      painter: TopFloatingShapesPainter(_waveController.value),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, _) {
                return ClipPath(
                  clipper: ImprovedBottomWaveClipper(_waveController.value),
                  child: Container(
                    height: size.height * 0.20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primary,
                          AppTheme.primary.withOpacity(0.9),
                          const Color(0xFF60A5FA),
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                    child: CustomPaint(
                      painter: BottomFloatingShapesPainter(
                        _waveController.value,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo.png',
                              height: 70,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              color: Colors.white.withOpacity(0.92),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                28,
                                34,
                                28,
                                30,
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) =>
                                          LinearGradient(
                                            colors: [
                                              AppTheme.primary,
                                              AppTheme.primary.withOpacity(
                                                0.75,
                                              ),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ).createShader(bounds),
                                      child: const Text(
                                        "Siply",
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: -0.5,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      "Sign in to continue",
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    _buildModernTextField(
                                      controller: _emailController,
                                      label: 'Email Address',
                                      hint: 'your@email.com',
                                      prefixIcon: Icons.email_outlined,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (value) {
                                        final v = value?.trim() ?? '';
                                        if (v.isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        if (!v.contains('@')) {
                                          return 'Please enter a valid email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 18),
                                    _buildModernTextField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      hint: '••••••••',
                                      prefixIcon: Icons.lock_outline,
                                      obscureText: !_isPasswordVisible,
                                      validator: (value) {
                                        final v = value ?? '';
                                        if (v.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        if (v.length < 6) {
                                          return 'Password must be at least 6 characters';
                                        }
                                        return null;
                                      },
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: AppTheme.primary,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          setState(
                                            () => _isPasswordVisible =
                                                !_isPasswordVisible,
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Container(
                                      width: double.infinity,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: LinearGradient(
                                          colors: [
                                            AppTheme.primary,
                                            AppTheme.primary.withOpacity(0.85),
                                          ],
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primary.withOpacity(
                                              0.35,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: ElevatedButton(
                                        onPressed: _isLoading
                                            ? null
                                            : _handleLogin,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                              )
                                            : const Text(
                                                'Sign In',
                                                style: TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Don\'t have an account? ',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () => Navigator.pushNamed(
                                            context,
                                            '/signup',
                                          ),
                                          child: Text(
                                            'Sign Up',
                                            style: TextStyle(
                                              color: AppTheme.primary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* waves/painters (same as your current ones) */

class ImprovedTopWaveClipper extends CustomClipper<Path> {
  final double animation;
  ImprovedTopWaveClipper(this.animation);

  @override
  Path getClip(Size size) {
    final path = Path();
    final waveHeight = 20.0;

    path.lineTo(0, size.height * 0.75);

    for (int i = 0; i < 3; i++) {
      final startX = size.width * (i / 3);
      final endX = size.width * ((i + 1) / 3);
      final midX = (startX + endX) / 2;

      final offset = math.sin(animation * math.pi * 2 + i * math.pi / 1.5);
      final controlY = size.height * 0.8 + waveHeight * offset;
      final endY =
          size.height * 0.82 +
          waveHeight *
              math.sin(animation * math.pi * 2 + (i + 1) * math.pi / 1.5);

      path.quadraticBezierTo(midX, controlY, endX, endY);
    }

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(ImprovedTopWaveClipper oldClipper) =>
      oldClipper.animation != animation;
}

class ImprovedBottomWaveClipper extends CustomClipper<Path> {
  final double animation;
  final double offset;

  ImprovedBottomWaveClipper(this.animation, {this.offset = 0.0});

  @override
  Path getClip(Size size) {
    final path = Path();
    final waveHeight = 18.0;

    path.moveTo(0, size.height * (0.18 + offset * 0.1));

    for (int i = 0; i < 3; i++) {
      final startX = size.width * (i / 3);
      final endX = size.width * ((i + 1) / 3);
      final midX = (startX + endX) / 2;

      final animOffset = animation * math.pi * 2 + i * math.pi / 1.8 + offset;
      final controlY = size.height * 0.2 + waveHeight * math.sin(animOffset);
      final endY =
          size.height * 0.22 +
          waveHeight *
              math.sin(
                animation * math.pi * 2 + (i + 1) * math.pi / 1.8 + offset,
              );

      path.quadraticBezierTo(midX, controlY, endX, endY);
    }

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(ImprovedBottomWaveClipper oldClipper) =>
      oldClipper.animation != animation || oldClipper.offset != offset;
}

class TopFloatingShapesPainter extends CustomPainter {
  final double animation;
  TopFloatingShapesPainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final offset = (animation * 0.6 + i * 0.2) % 1.0;
      final x = size.width * (0.1 + i * 0.2);
      final y = size.height * (0.15 + offset * 0.5);
      final radius = (20 + i * 12).toDouble();

      paint.color = Colors.white.withOpacity(0.08 + (i % 2) * 0.04);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    for (int i = 0; i < 3; i++) {
      final offset = (animation * 0.5 + i * 0.33) % 1.0;
      final x = size.width * (0.15 + i * 0.35);
      final y = size.height * (0.25 + offset * 0.4);

      paint.color = Colors.white.withOpacity(0.06);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: 50, height: 50),
        const Radius.circular(12),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(TopFloatingShapesPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class BottomFloatingShapesPainter extends CustomPainter {
  final double animation;
  BottomFloatingShapesPainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 4; i++) {
      final offset = (animation * 0.7 + i * 0.25) % 1.0;
      final x = size.width * (0.15 + i * 0.25);
      final y = size.height * (0.3 + offset * 0.35);
      final radius = (18 + i * 10).toDouble();

      paint.color = Colors.white.withOpacity(0.12 - i * 0.02);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    for (int i = 0; i < 2; i++) {
      final offset = (animation * 0.4 + i * 0.5) % 1.0;
      final x = size.width * (0.3 + i * 0.4);
      final y = size.height * (0.4 + offset * 0.3);

      paint.color = Colors.white.withOpacity(0.08);
      canvas.drawCircle(Offset(x, y), 15, paint);
    }
  }

  @override
  bool shouldRepaint(BottomFloatingShapesPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
