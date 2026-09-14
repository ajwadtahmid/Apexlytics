import 'package:flutter/material.dart';
import '../constants/weapon_constants.dart';
import '../models/player_stats.dart';
import '../utils/formatting/format.dart';
import '../utils/theme.dart';
import '../utils/formatting/weapon_utils.dart';
import 'stat_display.dart';
import 'surface_card.dart';

const _kWeaponTypeOrder = [
  WeaponType.assaultRifle,
  WeaponType.smg,
  WeaponType.lmg,
  WeaponType.marksman,
  WeaponType.sniper,
  WeaponType.pistol,
  WeaponType.shotgun,
];

class WeaponStatsSection extends StatelessWidget {
  final List<LegendStat> legendStats;

  const WeaponStatsSection({super.key, required this.legendStats});

  @override
  Widget build(BuildContext context) {
    final weaponStats = extractWeaponStats(legendStats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _kWeaponTypeOrder.map((type) {
        final weapons = kWeaponsByType[type] ?? [];
        return _WeaponTypeGroup(
          type: type,
          weapons: weapons,
          weaponStats: weaponStats,
        );
      }).toList(),
    );
  }
}

class _WeaponTypeGroup extends StatelessWidget {
  final WeaponType type;
  final List<Weapon> weapons;
  final Map<Weapon, Map<String, int>> weaponStats;

  const _WeaponTypeGroup({
    required this.type,
    required this.weapons,
    required this.weaponStats,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          type.displayName.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        SurfaceCard(
          child: Column(
            children: weapons.indexed.map((record) {
              final (index, weapon) = record;
              final isLast = index == weapons.length - 1;
              final stats = weaponStats[weapon];
              return Column(
                children: [
                  _WeaponRow(weapon: weapon, stats: stats),
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
    );
  }
}

class _WeaponRow extends StatelessWidget {
  final Weapon weapon;
  final Map<String, int>? stats;

  const _WeaponRow({required this.weapon, this.stats});

  @override
  Widget build(BuildContext context) {
    int? kills;
    int? damage;
    if (stats != null) {
      for (final e in stats!.entries) {
        // Keys are lowercased display names: "[weapon] kills" / "[weapon] damage".
        // Use suffix matching to avoid a hypothetical "damage from kills" key
        // matching both fields.
        if (e.key == 'kills' || e.key.endsWith(' kills')) kills = e.value;
        if (e.key == 'damage' || e.key.endsWith(' damage')) damage = e.value;
      }
    }
    final hasStats = kills != null || damage != null;
    final damagePerKill = (kills != null && kills > 0 && damage != null)
        ? (damage / kills).round()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.md,
        vertical: 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 36,
            child: Image.asset(
              weapon.assetPath,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (ctx, err, trace) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weapon.fullName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: hasStats ? FontWeight.w500 : FontWeight.normal,
                    color: hasStats ? AppTheme.textPrimary : AppTheme.muted,
                  ),
                ),
                if (hasStats) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (kills != null)
                        StatDisplay(
                          label: 'Kills',
                          value: formatNumber(kills),
                          compact: true,
                        ),
                      if (damage != null) ...[
                        const SizedBox(width: 5),
                        StatDisplay(
                          label: 'Damage',
                          value: formatNumber(damage),
                          compact: true,
                        ),
                      ],
                      if (damagePerKill != null) ...[
                        const SizedBox(width: 5),
                        StatDisplay(
                          label: 'Damage per Kill',
                          value: formatNumber(damagePerKill),
                          highlight: true,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
