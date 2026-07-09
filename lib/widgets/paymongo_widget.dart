import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class PayMongoWidget extends StatelessWidget {
  final double amount;
  final String methodLabel;

  const PayMongoWidget({
    super.key,
    required this.amount,
    this.methodLabel = 'QRPh via PayMongo',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.payment, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$methodLabel (₱${amount.toStringAsFixed(2)})',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
