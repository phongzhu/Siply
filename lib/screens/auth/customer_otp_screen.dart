import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_theme.dart';

class CustomerOTPScreen extends StatefulWidget {
  static const route = '/customer/otp';

  final String email;
  final String password;

  final String firstName;
  final String middleName;
  final String lastName;
  final String extensionName;
  final String contactNumber;

  const CustomerOTPScreen({
    super.key,
    required this.email,
    required this.password,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.extensionName,
    required this.contactNumber,
  });

  @override
  State<CustomerOTPScreen> createState() => _CustomerOTPScreenState();
}

class _CustomerOTPScreenState extends State<CustomerOTPScreen> {
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  bool _loading = false;

  bool _canResend = true;
  int _resendSeconds = 0;
  static const int _resendCooldown = 30;
  Timer? _timer;

  SupabaseClient get _client => Supabase.instance.client;

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() {
          _resendSeconds = 0;
          _canResend = true;
        });
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  void _focusNextEmpty() {
    for (int i = 0; i < 6; i++) {
      if (_otpControllers[i].text.isEmpty) {
        _focusNodes[i].requestFocus();
        return;
      }
    }
    _focusNodes[5].unfocus();
  }

  void _fillFromString(String raw) {
    final code = raw.replaceAll(RegExp(r'[^0-9]'), '');
    for (int i = 0; i < 6; i++) {
      _otpControllers[i].text = (i < code.length) ? code[i] : '';
    }
    _focusNextEmpty();
  }

  KeyEventResult _onKey(int i, FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_otpControllers[i].text.isEmpty && i > 0) {
        _focusNodes[i - 1].requestFocus();
        _otpControllers[i - 1].clear();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _verifyOtpAndCreateProfile() async {
    final token = _otpCode;

    if (token.length != 6 || token.contains(RegExp(r'[^0-9]'))) {
      _toast('Please enter the complete 6-digit code');
      return;
    }

    final pw = widget.password;
    if (pw.isEmpty || pw.length < 6) {
      _toast('Password is required (min 6 chars).');
      return;
    }

    setState(() => _loading = true);
    try {
      // ✅ Verify OTP against REAL EMAIL
      final res = await _client.auth.verifyOTP(
        email: widget.email,
        token: token,
        type: OtpType.email,
      );

      final authUser = res.user;
      if (authUser == null) {
        throw Exception('Verification failed (no user session).');
      }

      // ✅ Set password ONCE for this Auth user
      // (If already set, Supabase may throw—safe to ignore)
      try {
        await _client.auth.updateUser(UserAttributes(password: pw));
      } catch (_) {}

      // ✅ Create/Upsert customer role profile row
      await _client.from('users').upsert({
        'auth_user_id': authUser.id,
        'role': 'customer',
        'user_email': widget.email.toLowerCase(),
        'first_name': widget.firstName.trim(),
        'middle_name': widget.middleName.trim().isEmpty
            ? null
            : widget.middleName.trim(),
        'last_name': widget.lastName.trim(),
        'extension_name': widget.extensionName.trim().isEmpty
            ? null
            : widget.extensionName.trim(),
        'contact_number': widget.contactNumber.trim().isEmpty
            ? null
            : widget.contactNumber.trim(),
        'status': 'active',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'auth_user_id,role');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      _toast('Verification failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend || _loading) return;

    setState(() {
      _loading = true;
      _canResend = false;
      _resendSeconds = _resendCooldown;
    });

    try {
      // ✅ resend to REAL EMAIL
      await _client.auth.signInWithOtp(
        email: widget.email.toLowerCase(),
        shouldCreateUser: true,
      );
      _toast('New code sent to ${widget.email}');
      _startResendTimer();
    } catch (e) {
      _toast('Failed to resend code: ${e.toString()}');
      if (mounted) {
        setState(() {
          _canResend = true;
          _resendSeconds = 0;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _otpBox(int i, Color blue, TextStyle? textStyle) {
    return Container(
      width: 50,
      height: 56,
      margin: EdgeInsets.symmetric(horizontal: i == 2 ? 8 : 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[i].hasFocus ? blue : blue.withOpacity(0.18),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: blue.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Focus(
        focusNode: _focusNodes[i],
        onKeyEvent: (node, event) => _onKey(i, node, event),
        child: TextField(
          controller: _otpControllers[i],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          enabled: !_loading,
          style: textStyle,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.only(bottom: 8),
          ),
          onTap: () {
            _otpControllers[i].selection = TextSelection(
              baseOffset: 0,
              extentOffset: _otpControllers[i].text.length,
            );
          },
          onChanged: (val) {
            if (val.length > 1) {
              _fillFromString(val);
              return;
            }

            if (val.isNotEmpty && i < 5) {
              _focusNodes[i + 1].requestFocus();
            } else if (val.isEmpty && i > 0) {
              _focusNodes[i - 1].requestFocus();
            }

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _focusNextEmpty();
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blue = AppTheme.primary;

    final otpTextStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: blue,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mail_outline_rounded, size: 64, color: blue),
              ),
              const SizedBox(height: 32),
              Text(
                'Verify Your Email',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification code to',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: blue,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: _focusNextEmpty,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (i) => _otpBox(i, blue, otpTextStyle),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verifyOtpAndCreateProfile,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Verify Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive the code?",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: (_loading || !_canResend) ? null : _resendOtp,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _canResend
                        ? Text(
                            'Resend',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.primaryColor,
                            ),
                          )
                        : Text(
                            'Resend in ${_resendSeconds}s',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[400],
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
