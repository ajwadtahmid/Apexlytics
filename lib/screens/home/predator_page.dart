import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../constants/api_constants.dart';
import '../../constants/ui_strings.dart';
import '../../models/predator.dart';
import '../../utils/formatting/format.dart' show formatNumber, timeAgo;
import '../../utils/formatting/platform_utils.dart';
import '../../utils/theme.dart';
import '../../widgets/info_sheet.dart';
import '../../widgets/surface_card.dart';

class PredatorPage extends StatelessWidget {
  final PredatorResponse data;

  /// The platform of the selected profile, marked on its card; null with no
  /// player set up.
  final String? yourPlatform;
  const PredatorPage({super.key, required this.data, this.yourPlatform});

  @override
  Widget build(BuildContext context) {
    final entries = ApiConstants.platforms
        .map((key) => (key, ApiConstants.labelFor(key), data.forPlatform(key)))
        .where((e) => e.$3 != null)
        .toList();
    // The oldest reading, so "updated" never claims more than every card has.
    final times = [for (final e in entries) ?e.$3!.updatedAt];
    final oldest = times.isEmpty
        ? null
        : times.reduce((a, b) => a.isBefore(b) ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pred Cutoff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About the cutoff',
            onPressed: () => showInfoSheet(
              context,
              title: 'About the cutoff',
              lines: const [predatorPageInfo],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          ...entries.map(
            (e) => PlatformCard(
              platformKey: e.$1,
              name: e.$2,
              info: e.$3!,
              isYours: e.$1 == yourPlatform,
            ),
          ),
          if (oldest != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.xs),
              child: Text(
                'Updated ${timeAgo(oldest)}',
                textAlign: TextAlign.center,
                style: AppTheme.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class PlatformCard extends StatelessWidget {
  final String platformKey;
  final String name;
  final PlatformPredator info;

  /// Whether this is the platform of the selected profile.
  final bool isYours;

  const PlatformCard({
    super.key,
    required this.platformKey,
    required this.name,
    required this.info,
    this.isYours = false,
  });

  static Widget _icon(String platformKey) {
    final p = platformIconFor(platformKey);
    return FaIcon(p.icon, color: p.color, size: 16);
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: AppTheme.sm),
      padding: const EdgeInsets.all(AppTheme.md),
      border: isYours ? Border.all(color: AppTheme.accent) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _icon(platformKey),
              const SizedBox(width: AppTheme.xs),
              Text(
                name.toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (isYours)
                const Text(
                  'YOUR PLATFORM',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatNumber(info.minRp),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'RP',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${formatNumber(info.totalMastersAndPreds)} Masters + Preds',
            style: AppTheme.captionLarge,
          ),
        ],
      ),
    );
  }
}
