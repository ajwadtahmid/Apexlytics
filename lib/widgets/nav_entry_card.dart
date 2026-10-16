import 'package:flutter/material.dart';

import '../utils/theme.dart';
import 'surface_card.dart';

/// A full-width tappable row, `[icon] Title  >`, that opens a detail screen.
class NavEntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const NavEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.md),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.accent),
              const SizedBox(width: AppTheme.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}
