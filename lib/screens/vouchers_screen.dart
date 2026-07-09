import 'package:flutter/material.dart';
import '../utils/dummy_data.dart';
import '../widgets/section_header.dart';
import '../widgets/voucher_card.dart';

class VouchersScreen extends StatelessWidget {
  static const route = '/vouchers';
  const VouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vouchers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(
              title: 'Digital Vouchers',
              subtitle: 'Centralized promos and rewards (placeholder data).',
            ),
            ...DummyData.vouchers.map((v) => VoucherCard(voucher: v)),
          ],
        ),
      ),
    );
  }
}
