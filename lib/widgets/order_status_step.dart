import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class OrderStatusStep extends StatelessWidget {
  final int
  currentStep; // 0: Ordered, 1: Preparing, 2: Collection, 3: Completed
  const OrderStatusStep({super.key, required this.currentStep});

  static const _labels = ['Ordered', 'Preparing', 'Collection', 'Completed'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(4, (i) {
        final isActive = i == currentStep;
        final isDone = i < currentStep;
        return Expanded(
          child: Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary
                      : isDone
                      ? Colors.green[200]
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primary
                        : isDone
                        ? Colors.green
                        : Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    i == 0
                        ? Icons.receipt_long
                        : i == 1
                        ? Icons.local_cafe
                        : i == 2
                        ? Icons.shopping_bag
                        : Icons.verified,
                    color: isActive || isDone ? Colors.white : Colors.grey[500],
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _labels[i],
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive
                      ? AppTheme.primary
                      : isDone
                      ? Colors.green
                      : Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
