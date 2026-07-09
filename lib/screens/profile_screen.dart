import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  static const route = '/profile';
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _backgroundController;
  SupabaseClient get _client => Supabase.instance.client;
  late Future<ProfileData> _profileFuture;
  late Future<Map<String, Map<String, List<String>>>> _addressDataFuture;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _profileFuture = _loadProfile();
    _addressDataFuture = _loadAddressData();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchUserRow() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return null;

    final preferredRows = await _client
        .from('users')
        .select(
          'user_id, first_name, last_name, middle_name, extension_name, user_email, contact_number, street, barangay, city, province',
        )
        .eq('auth_user_id', authUser.id)
        .eq('role', 'customer')
        .limit(1);

    if ((preferredRows as List).isNotEmpty) {
      return (preferredRows.first as Map).cast<String, dynamic>();
    }

    final rows = await _client
        .from('users')
        .select(
          'user_id, first_name, last_name, middle_name, extension_name, user_email, contact_number, street, barangay, city, province',
        )
        .eq('auth_user_id', authUser.id)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return (rows.first as Map).cast<String, dynamic>();
  }

  Future<ProfileData> _loadProfile() async {
    final row = await _fetchUserRow();
    if (row == null) {
      throw Exception('Profile not found. Please log in again.');
    }

    final userId = (row['user_id'] as num).toInt();
    final ordersRows = await _client
        .from('orders')
        .select('order_id')
        .eq('user_id', userId);
    final totalOrders = (ordersRows as List).length;

    return ProfileData(
      userId: userId,
      firstName: (row['first_name'] ?? '').toString(),
      lastName: (row['last_name'] ?? '').toString(),
      middleName: (row['middle_name'] ?? '').toString(),
      extensionName: (row['extension_name'] ?? '').toString(),
      email: (row['user_email'] ?? '').toString(),
      contactNumber: (row['contact_number'] ?? '').toString(),
      street: (row['street'] ?? '').toString(),
      barangay: (row['barangay'] ?? '').toString(),
      city: (row['city'] ?? '').toString(),
      province: (row['province'] ?? '').toString(),
      totalOrders: totalOrders,
    );
  }

  Future<Map<String, Map<String, List<String>>>> _loadAddressData() async {
    final jsonString = await rootBundle.loadString(
      'lib/components/philippine_provinces_cities_municipalities_and_barangays_2019v2.json',
    );
    final data = json.decode(jsonString) as Map<String, dynamic>;
    final result = <String, Map<String, List<String>>>{};

    for (final regionEntry in data.values) {
      final regionMap = regionEntry as Map<String, dynamic>;
      final provinceList =
          (regionMap['province_list'] as Map<String, dynamic>?) ?? {};
      for (final provinceEntry in provinceList.entries) {
        final provinceName = provinceEntry.key;
        final provinceMap = provinceEntry.value as Map<String, dynamic>;
        final municipalityList =
            (provinceMap['municipality_list'] as Map<String, dynamic>?) ?? {};
        final cityMap = <String, List<String>>{};
        for (final municipalityEntry in municipalityList.entries) {
          final municipalityName = municipalityEntry.key;
          final municipalityMap =
              municipalityEntry.value as Map<String, dynamic>;
          final barangayList =
              (municipalityMap['barangay_list'] as List<dynamic>?)
                  ?.map((item) => item.toString())
                  .toList() ??
              <String>[];
          barangayList.sort();
          cityMap[municipalityName] = barangayList;
        }
        final cityNames = cityMap.keys.toList()..sort();
        final sortedCityMap = <String, List<String>>{};
        for (final cityName in cityNames) {
          sortedCityMap[cityName] = cityMap[cityName] ?? <String>[];
        }
        result[provinceName] = sortedCityMap;
      }
    }

    final provinceNames = result.keys.toList()..sort();
    final sortedResult = <String, Map<String, List<String>>>{};
    for (final provinceName in provinceNames) {
      sortedResult[provinceName] = result[provinceName] ?? {};
    }
    return sortedResult;
  }

  Future<void> _refreshProfile() async {
    final future = _loadProfile();
    setState(() {
      _profileFuture = future;
    });
    await future;
  }

  String _formatFullName(ProfileData profile) {
    final parts = <String>[];
    if (profile.firstName.trim().isNotEmpty) {
      parts.add(profile.firstName.trim());
    }
    if (profile.middleName.trim().isNotEmpty) {
      parts.add(profile.middleName.trim());
    }
    if (profile.lastName.trim().isNotEmpty) {
      parts.add(profile.lastName.trim());
    }
    if (profile.extensionName.trim().isNotEmpty) {
      parts.add(profile.extensionName.trim());
    }
    return parts.isEmpty ? 'Profile' : parts.join(' ');
  }

  Future<void> _showEditProfileSheet(ProfileData profile) async {
    final addressData = await _addressDataFuture.catchError(
      (_) => <String, Map<String, List<String>>>{},
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _EditProfileSheet(
          profile: profile,
          client: _client,
          addressData: addressData,
        );
      },
    );

    if (saved == true) {
      await _refreshProfile();
      if (!mounted) return;
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFFF6F4FB),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Saved',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: const Text(
            'Your address has been saved.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'OK',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.only(bottom: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated background matching login/home
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary,
                      AppTheme.primary.withOpacity(0.85),
                      AppTheme.primary.withOpacity(0.7),
                    ],
                    stops: [
                      0.0,
                      0.5 +
                          math.sin(_backgroundController.value * math.pi * 2) *
                              0.1,
                      1.0,
                    ],
                  ),
                ),
              );
            },
          ),

          // Decorative shapes
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, child) {
              return Stack(
                children: [
                  Positioned(
                    top: -50,
                    right: -80,
                    child: Transform.rotate(
                      angle: _backgroundController.value * math.pi * 2,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withOpacity(0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 120,
                    left: -60,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.06),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Main content
          SafeArea(
            child: FutureBuilder<ProfileData>(
              future: _profileFuture,
              builder: (context, snapshot) {
                final loading =
                    snapshot.connectionState != ConnectionState.done;
                final profile = snapshot.data;
                return Column(
                  children: [
                    // Custom App Bar
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: const [
                          Text(
                            'Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Profile header section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Column(
                        children: [
                          // Avatar with glow
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.3),
                                  Colors.white.withOpacity(0.1),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              child: Icon(
                                Icons.person,
                                color: AppTheme.primary,
                                size: 50,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Name
                          Text(
                            profile == null
                                ? 'Loading...'
                                : _formatFullName(profile),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Email
                          Text(
                            profile?.email ?? '',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Edit Profile Button
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: loading || profile == null
                                    ? null
                                    : () => _showEditProfileSheet(profile),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Edit Profile',
                                        style: TextStyle(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content area
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF7F7FB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const SizedBox(height: 8),

                            if (snapshot.hasError)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  'Failed to load profile: ${snapshot.error}',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),

                            // Stats Cards
                            Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    icon: Icons.receipt_long_outlined,
                                    value: loading || profile == null
                                        ? '—'
                                        : profile.totalOrders.toString(),
                                    label: 'Total Orders',
                                    onTap: () {},
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Section title
                            const Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 12),
                              child: Text(
                                'Support',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                ),
                              ),
                            ),

                            _GlassCard(
                              child: Column(
                                children: [
                                  _MenuTile(
                                    icon: Icons.help_outline,
                                    title: 'Help Center',
                                    subtitle: 'Get help with your orders',
                                    onTap: () {
                                      _showHelpCenter();
                                    },
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.withOpacity(0.1),
                                  ),
                                  _MenuTile(
                                    icon: Icons.policy_outlined,
                                    title: 'Terms & Policies',
                                    subtitle: 'Privacy policy and terms',
                                    onTap: () {
                                      _showTermsAndPolicies();
                                    },
                                  ),
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.withOpacity(0.1),
                                  ),
                                  _MenuTile(
                                    icon: Icons.info_outline,
                                    title: 'About Siply',
                                    subtitle: 'Version 1.0.0',
                                    onTap: () {
                                      _showAboutSiply();
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Logout button
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade400,
                                    Colors.red.shade500,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: _showLogoutDialog,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.logout,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Log Out',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHelpCenter() async {
    await _showInfoModal(
      title: 'Help Center',
      sections: const [
        _InfoSection(
          heading: 'Order Status and Queue',
          body:
              'Track your order in real time from the Order Status screen. If the status has not updated for more than 20 minutes, contact the store using your order reference number.',
        ),
        _InfoSection(
          heading: 'Changes and Cancellations',
          body:
              'You can request changes before the store starts preparing your order. Once preparation begins, cancellation may no longer be possible and store policy will apply.',
        ),
        _InfoSection(
          heading: 'Payments and Refunds',
          body:
              'Digital payments are processed securely. If you were charged for an unfulfilled order, refund reviews are typically completed within 3 to 7 business days.',
        ),
        _InfoSection(
          heading: 'Support Hours',
          body:
              'Support is available daily from 8:00 AM to 8:00 PM (Philippine Time). Include your order reference number for faster assistance.',
        ),
      ],
    );
  }

  Future<void> _showTermsAndPolicies() async {
    await _showInfoModal(
      title: 'Terms & Policies',
      sections: const [
        _InfoSection(
          heading: 'Terms of Use',
          body:
              'By using Siply, you agree to provide accurate account information, follow store rules, and use the app only for lawful transactions.',
        ),
        _InfoSection(
          heading: 'Privacy Policy',
          body:
              'Siply collects account, order, and location details you provide to process orders, improve service quality, and send transaction-related notifications.',
        ),
        _InfoSection(
          heading: 'Data Protection',
          body:
              'Personal data is handled with reasonable administrative and technical safeguards. Data access is limited to authorized systems and personnel.',
        ),
        _InfoSection(
          heading: 'Policy Updates',
          body:
              'Terms and privacy practices may be updated to reflect legal, technical, or service changes. Continued use of the app means you accept updated policies.',
        ),
      ],
    );
  }

  Future<void> _showAboutSiply() async {
    await _showInfoModal(
      title: 'About Siply',
      sections: const [
        _InfoSection(
          heading: 'What Siply Does',
          body:
              'Siply is a queue-skip ordering app that helps customers order ahead, reduce waiting time, and pick up food and drinks more efficiently.',
        ),
        _InfoSection(
          heading: 'Our Mission',
          body:
              'We aim to make everyday ordering faster and more reliable for both customers and local stores through clear order tracking and smoother pickup flow.',
        ),
        _InfoSection(
          heading: 'Current Version',
          body:
              'You are using Siply version 1.0.0. The app is continuously improved for stability, speed, and better order transparency.',
        ),
        _InfoSection(
          heading: 'Contact',
          body:
              'For business inquiries or support escalation, email support@siply.app with your account email and order reference number.',
        ),
      ],
    );
  }

  Future<void> _showInfoModal({
    required String title,
    required List<_InfoSection> sections,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: sections.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final section = sections[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7FB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                section.heading,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                section.body,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _client.auth.signOut();
                if (!mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Logout failed: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection {
  final String heading;
  final String body;

  const _InfoSection({required this.heading, required this.body});
}

/// ---------- UI COMPONENTS ----------

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withOpacity(0.15),
                        AppTheme.primary.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.15), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withOpacity(0.15),
                      AppTheme.primary.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileData {
  final int userId;
  final String firstName;
  final String lastName;
  final String middleName;
  final String extensionName;
  final String email;
  final String contactNumber;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final int totalOrders;

  const ProfileData({
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.extensionName,
    required this.email,
    required this.contactNumber,
    required this.street,
    required this.barangay,
    required this.city,
    required this.province,
    required this.totalOrders,
  });
}

class _EditProfileSheet extends StatefulWidget {
  final ProfileData profile;
  final SupabaseClient client;
  final Map<String, Map<String, List<String>>> addressData;

  const _EditProfileSheet({
    required this.profile,
    required this.client,
    required this.addressData,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController firstName;
  late final TextEditingController lastName;
  late final TextEditingController middleName;
  late final TextEditingController extensionName;
  late final TextEditingController email;
  late final TextEditingController contactNumber;
  late final TextEditingController street;
  late final TextEditingController barangay;
  late final TextEditingController city;
  late final TextEditingController province;

  bool saving = false;
  late final List<String> provinces;
  late final bool hasAddressData;
  String? selectedProvince;
  String? selectedCity;
  String? selectedBarangay;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    firstName = TextEditingController(text: profile.firstName);
    lastName = TextEditingController(text: profile.lastName);
    middleName = TextEditingController(text: profile.middleName);
    extensionName = TextEditingController(text: profile.extensionName);
    email = TextEditingController(text: profile.email);
    contactNumber = TextEditingController(text: profile.contactNumber);
    street = TextEditingController(text: profile.street);
    barangay = TextEditingController(text: profile.barangay);
    city = TextEditingController(text: profile.city);
    province = TextEditingController(text: profile.province);

    provinces = widget.addressData.keys.toList()..sort();
    hasAddressData = provinces.isNotEmpty;

    selectedProvince = _selectIfPresent(profile.province, provinces);
    if (selectedProvince != null) {
      final cities = widget.addressData[selectedProvince]!.keys.toList()
        ..sort();
      selectedCity = _selectIfPresent(profile.city, cities);
      if (selectedCity != null) {
        final barangays =
            widget.addressData[selectedProvince]![selectedCity] ?? <String>[];
        selectedBarangay = _selectIfPresent(profile.barangay, barangays);
      }
    }

    if (hasAddressData) {
      province.text = selectedProvince ?? '';
      city.text = selectedCity ?? '';
      barangay.text = selectedBarangay ?? '';
    }
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    middleName.dispose();
    extensionName.dispose();
    email.dispose();
    contactNumber.dispose();
    street.dispose();
    barangay.dispose();
    city.dispose();
    province.dispose();
    super.dispose();
  }

  String? _selectIfPresent(String value, Iterable<String> options) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return options.contains(trimmed) ? trimmed : null;
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) {
      return;
    }
    setState(() => saving = true);
    try {
      final authUser = widget.client.auth.currentUser;
      if (authUser == null) {
        throw Exception('Please log in again to update profile.');
      }

      final updatedRows = await widget.client
          .from('users')
          .update({
            'first_name': firstName.text.trim(),
            'middle_name': middleName.text.trim(),
            'last_name': lastName.text.trim(),
            'extension_name': extensionName.text.trim(),
            'user_email': email.text.trim(),
            'contact_number': contactNumber.text.trim(),
            'street': street.text.trim(),
            'barangay': barangay.text.trim(),
            'city': city.text.trim(),
            'province': province.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('auth_user_id', authUser.id)
          .eq('role', 'customer')
          .select('user_id');

      if ((updatedRows as List).isEmpty) {
        throw Exception('Profile update blocked. Check permissions.');
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: firstName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'First name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: middleName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Middle name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lastName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Last name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Last name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: extensionName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Extension name',
                  hintText: 'Jr, Sr, III',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: email,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: contactNumber,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Contact number'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: street,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Street'),
              ),
              const SizedBox(height: 12),
              if (hasAddressData) ...[
                DropdownButtonFormField<String>(
                  initialValue: selectedProvince,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Province'),
                  items: provinces
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedProvince = value;
                      province.text = value ?? '';
                      selectedCity = null;
                      city.text = '';
                      selectedBarangay = null;
                      barangay.text = '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCity,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'City / Municipality',
                  ),
                  items:
                      (selectedProvince == null
                              ? <String>[]
                              : (widget.addressData[selectedProvince]!.keys
                                    .toList()
                                  ..sort()))
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: selectedProvince == null
                      ? null
                      : (value) {
                          setState(() {
                            selectedCity = value;
                            city.text = value ?? '';
                            selectedBarangay = null;
                            barangay.text = '';
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedBarangay,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Barangay'),
                  items:
                      (selectedProvince == null || selectedCity == null
                              ? <String>[]
                              : (widget.addressData[selectedProvince]![selectedCity] ??
                                    <String>[]))
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: selectedCity == null
                      ? null
                      : (value) {
                          setState(() {
                            selectedBarangay = value;
                            barangay.text = value ?? '';
                          });
                        },
                ),
              ] else ...[
                TextFormField(
                  controller: barangay,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Barangay'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: city,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'City'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: province,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Province'),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving ? null : _save,
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
