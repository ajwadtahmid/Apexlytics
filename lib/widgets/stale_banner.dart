import 'package:flutter/material.dart';
import '../utils/formatting/format.dart' show timeAgo;
import '../utils/theme.dart';

class StaleBanner extends StatelessWidget {
  final DateTime staleAt;
  const StaleBanner({super.key, required this.staleAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: AppTheme.sm,
      ),
      decoration: BoxDecoration(
        color: AppTheme.orange.withAlpha(25),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 14, color: AppTheme.orange),
          const SizedBox(width: 6),
          Text(
            'Last synced ${timeAgo(staleAt)}',
            style: const TextStyle(color: AppTheme.orange, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
