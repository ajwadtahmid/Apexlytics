import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../constants/api_constants.dart';
import '../../constants/ui_strings.dart';
import '../../models/predator.dart';
import '../../utils/formatting/format.dart' show formatNumber, timeAgo;
import '../../utils/theme.dart';
import '../../widgets/surface_card.dart';

class PredatorPage extends StatelessWidget {
  final PredatorResponse data;
  const PredatorPage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = ApiConstants.platforms
        .map((key) => (key, ApiConstants.labelFor(key), data.forPlatform(key)))
        .where((e) => e.$3 != null)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Pred Cutoff')),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          ...entries.map(
            (e) => PlatformCard(platformKey: e.$1, name: e.$2, info: e.$3!),
          ),
          const SizedBox(height: AppTheme.md),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.sm),
            child: Text(
              predatorPageInfo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 12,
                height: 1.5,
              ),
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

  const PlatformCard({
    super.key,
    required this.platformKey,
    required this.name,
    required this.info,
  });

  static Widget _icon(String platformKey) => switch (platformKey) {
    'PS4' => const FaIcon(
      FontAwesomeIcons.playstation,
      color: AppTheme.blue,
      size: 16,
    ),
    'X1' => const FaIcon(
      FontAwesomeIcons.xbox,
      color: AppTheme.green,
      size: 16,
    ),
    'SWITCH' => const FaIcon(
      FontAwesomeIcons.gamepad,
      color: AppTheme.red,
      size: 16,
    ),
    _ => const FaIcon(
      FontAwesomeIcons.desktop,
      color: AppTheme.muted,
      size: 16,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: AppTheme.sm),
      padding: const EdgeInsets.all(AppTheme.md),
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
              Text(
                info.updatedAt != null ? timeAgo(info.updatedAt!) : '—',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12),
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
            style: const TextStyle(color: AppTheme.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
