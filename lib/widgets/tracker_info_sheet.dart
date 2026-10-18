import 'package:flutter/material.dart';
import '../constants/api_constants.dart';
import '../utils/theme.dart';
import 'sheet_handle.dart';

void showTrackerInfoSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
          AppTheme.md,
          AppTheme.md,
          AppTheme.md,
          AppTheme.lg,
        ),
        children: [
          const SheetHandle(),
          const SizedBox(height: AppTheme.md),
          const Text(
            'Tracker Info',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppTheme.sm),
          const Text(
            'These are career totals for Battle Royale, not just ranked or '
            'this split. Each legend reports only the trackers it has '
            'equipped, so "—" means that tracker isn\'t reported, not zero.',
            style: AppTheme.caption,
          ),
          const SizedBox(height: AppTheme.lg),
          ..._buildTrackerInfoSection('Available Stats Calculations', const [
            ('Damage per Kill', 'BR Damage & BR Kills'),
            ('Avg Kills per Game', 'BR Kills & BR Games played'),
            ('Win Rate', 'BR Wins & BR Games played'),
            ('Revive Rate', 'BR Revives & BR Games played'),
            ('Top 3 Placement %', 'BR Top 3 & BR Games played'),
            ('Kills as Kill Leader %', 'BR Kills as kill leader & BR Kills'),
          ]),
          const SizedBox(height: AppTheme.md),
          ..._buildTrackerInfoSection('Helpful Links', const [
            ('Apex Legends Status', ApiConstants.apexStatusUrl),
          ]),
        ],
      ),
    ),
  );
}

List<Widget> _buildTrackerInfoSection(
  String title,
  List<(String, String)> items,
) {
  return [
    Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    ),
    const SizedBox(height: AppTheme.sm),
    Container(
      padding: const EdgeInsets.all(AppTheme.md),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.indexed.map((record) {
          final (index, item) = record;
          final isLast = index == items.length - 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: '${item.$1}: ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                    TextSpan(text: item.$2),
                  ],
                ),
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTheme.sm),
                  child: Divider(color: AppTheme.surface, height: 1),
                ),
            ],
          );
        }).toList(),
      ),
    ),
  ];
}
