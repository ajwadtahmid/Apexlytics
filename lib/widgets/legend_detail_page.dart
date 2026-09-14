import 'package:flutter/material.dart';
import '../constants/legend_constants.dart';
import '../constants/rank_constants.dart';
import '../constants/tracker_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/theme.dart';
import '../utils/tracking/legend_tracker_logic.dart';
import '../utils/formatting/tracker_utils.dart';
import 'legend_asset_image.dart';
import 'tracker_info_sheet.dart';

final _brPrefixPattern = RegExp(r'^BR\s+');
final _killsSuffixPattern = RegExp(r'\s+kills$');

LegendTracker? _findByDisplayName(
  List<LegendTracker> trackers,
  String displayName,
) => findTracker(trackers, (t) => t.displayName.toLowerCase() == displayName);

class LegendDetailPage extends StatelessWidget {
  final LegendStat legend;

  const LegendDetailPage({super.key, required this.legend});

  bool get _isCareer => legend.name == kCareerLegendName;
  String get _displayName => legendDisplayName(legend.name);
  String get _imageKey =>
      _isCareer ? 'career' : legend.name.toLowerCase().replaceAll(' ', '_');

  List<LegendTracker> get _displayTrackers =>
      deduplicateTrackers(legend.trackers);

  void _showTrackerInfo(BuildContext context) => showTrackerInfoSheet(context);

  @override
  Widget build(BuildContext context) {
    final info = kLegendsByName[legend.name.toLowerCase()];
    final raw = legend.trackers;
    final displayTrackers = _displayTrackers;

    // ── Stat lookups ─────────────────────────────────────────────────────────

    // Exact display-name matches (case-insensitive) to avoid substring collisions.
    final kills = _isCareer
        ? null
        : _findByDisplayName(raw, TrackerKeys.brKills);
    final wins = _isCareer ? null : _findByDisplayName(raw, TrackerKeys.brWins);
    final gamesPlayed = _isCareer
        ? null
        : _findByDisplayName(raw, TrackerKeys.brGamesPlayed);
    final killLeader = _isCareer
        ? null
        : _findByDisplayName(raw, TrackerKeys.brKillsAsKillLeader);
    final top3 = _isCareer ? null : _findByDisplayName(raw, TrackerKeys.brTop3);
    final revives = _isCareer
        ? null
        : _findByDisplayName(raw, TrackerKeys.brRevives);
    final damage = _isCareer
        ? null
        : _findByDisplayName(raw, TrackerKeys.brDamage);

    // ── Calculations ─────────────────────────────────────────────────────────

    final gamesPlayedValue = gamesPlayed?.value;
    final killsValue = kills?.value;
    final winsValue = wins?.value;

    final damagePerKill =
        (killsValue != null && killsValue > 0 && damage != null)
        ? (damage.value / killsValue).round()
        : null;
    final avgKillsPerGame =
        (killsValue != null && gamesPlayedValue != null && gamesPlayedValue > 0)
        ? killsValue / gamesPlayedValue
        : null;
    final winRate =
        (winsValue != null && gamesPlayedValue != null && gamesPlayedValue > 0)
        ? winsValue / gamesPlayedValue * 100
        : null;
    final reviveRate =
        (revives != null && gamesPlayedValue != null && gamesPlayedValue > 0)
        ? revives.value / gamesPlayedValue
        : null;
    final top3Pct =
        (top3 != null && gamesPlayedValue != null && gamesPlayedValue > 0)
        ? top3.value / gamesPlayedValue * 100
        : null;
    final killLeaderPct =
        (killLeader != null && killsValue != null && killsValue > 0)
        ? killLeader.value / killsValue * 100
        : null;

    final weaponCategories = !_isCareer
        ? findTopWeaponCategories(raw)
        : <LegendTracker>[];

    // ── Collect legend calc rows (ordered as specified) ───────────────────────

    final legendRows = <({String label, String value, List<String> sources})>[
      if (damagePerKill != null && damage != null && kills != null)
        (
          label: 'Damage per Kill',
          value: formatNumber(damagePerKill),
          sources: [damage.displayName, kills.displayName],
        ),
      if (avgKillsPerGame != null && kills != null && gamesPlayed != null)
        (
          label: 'Avg Kills per Game',
          value: avgKillsPerGame.toStringAsFixed(1),
          sources: [kills.displayName, gamesPlayed.displayName],
        ),
      if (winRate != null && wins != null && gamesPlayed != null)
        (
          label: 'Win Rate',
          value: '${winRate.toStringAsFixed(1)}%',
          sources: [wins.displayName, gamesPlayed.displayName],
        ),
      if (reviveRate != null && revives != null && gamesPlayed != null)
        (
          label: 'Revive Rate',
          value: reviveRate.toStringAsFixed(2),
          sources: [revives.displayName, gamesPlayed.displayName],
        ),
      if (top3Pct != null && top3 != null && gamesPlayed != null)
        (
          label: 'Top 3 Placement %',
          value: '${top3Pct.toStringAsFixed(1)}%',
          sources: [top3.displayName, gamesPlayed.displayName],
        ),
      if (killLeaderPct != null && killLeader != null && kills != null)
        (
          label: 'Kills as Kill Leader %',
          value: '${killLeaderPct.toStringAsFixed(1)}%',
          sources: [killLeader.displayName, kills.displayName],
        ),
    ];

    final showStatsSection =
        !_isCareer && (legendRows.isNotEmpty || weaponCategories.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showTrackerInfo(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.md),
        children: [
          // ── Hero card ──────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 150,
                    child: LegendAssetImage(
                      imageKey: _imageKey,
                      displayName: _displayName,
                      fallbackFontSize: 56,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _displayName,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (info != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: info.role.color.withAlpha(35),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                              ),
                              child: Text(
                                info.role.displayName,
                                style: TextStyle(
                                  color: info.role.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppTheme.md),

          // ── Stats ──────────────────────────────────────────────────
          if (showStatsSection) ...[
            const Text(
              'Stats',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.sm),

            // Legend calc rows
            if (legendRows.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Column(
                  children: legendRows.asMap().entries.map((entry) {
                    final row = entry.value;
                    final isLast = entry.key == legendRows.length - 1;
                    return _CalcRow(
                      label: row.label,
                      value: row.value,
                      sources: row.sources,
                      isLast: isLast,
                    );
                  }).toList(),
                ),
              ),

            // Top 3 weapon category card
            if (weaponCategories.isNotEmpty) ...[
              const SizedBox(height: AppTheme.md),
              const Text(
                'Top Weapon Categories',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppTheme.sm),
              _WeaponRankCard(weapons: weaponCategories),
            ],

            const SizedBox(height: AppTheme.md),
          ],

          // ── Trackers ───────────────────────────────────────────────
          if (displayTrackers.isNotEmpty) ...[
            const Text(
              'Trackers',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.sm),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                children: displayTrackers.asMap().entries.map((entry) {
                  final t = entry.value;
                  final isLast = entry.key == displayTrackers.length - 1;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.md,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              t.displayName,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              formatNumber(t.value),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        const Divider(
                          color: AppTheme.surface2,
                          height: 1,
                          indent: 16,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: AppTheme.md),
          ],

          const SizedBox(height: AppTheme.lg),
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> sources;
  final bool isLast;

  const _CalcRow({
    required this.label,
    required this.value,
    this.sources = const [],
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.md,
            vertical: 12,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 14,
                      ),
                    ),
                    if (sources.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'via ${sources.join(' & ')}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.accent2,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(color: AppTheme.surface2, height: 1, indent: 16),
      ],
    );
  }
}

class _WeaponRankCard extends StatelessWidget {
  final List<LegendTracker> weapons;
  const _WeaponRankCard({required this.weapons});

  // Medal colors: 1st place (gold), 2nd place (silver), 3rd place (bronze)
  static final _rankColors = [
    kRankLadder.firstWhere((r) => r.tier == 'Gold').color, // gold
    kRankLadder.firstWhere((r) => r.tier == 'Silver').color, // silver
    kRankLadder.firstWhere((r) => r.tier == 'Bronze').color, // bronze
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        children: weapons.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          final isLast = i == weapons.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.md,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: _rankColors[i.clamp(0, _rankColors.length - 1)],
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.displayName
                            .replaceFirst(_brPrefixPattern, '')
                            .replaceAll(_killsSuffixPattern, ''),
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      formatNumber(t.value),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.accent2,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(color: AppTheme.surface2, height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}
