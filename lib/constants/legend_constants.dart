import 'package:flutter/material.dart';

enum LegendRole { assault, controller, recon, skirmisher, support }

/// Role display order: Assault, Skirmisher, Recon, Support, Controller.
const List<LegendRole> kRoleDisplayOrder = [
  LegendRole.assault,
  LegendRole.skirmisher,
  LegendRole.recon,
  LegendRole.support,
  LegendRole.controller,
];

extension LegendRoleLabel on LegendRole {
  String get displayName => switch (this) {
    LegendRole.assault => 'Assault',
    LegendRole.controller => 'Controller',
    LegendRole.recon => 'Recon',
    LegendRole.skirmisher => 'Skirmisher',
    LegendRole.support => 'Support',
  };

  Color get color => switch (this) {
    LegendRole.assault => const Color(0xFFEF5350), // red
    LegendRole.controller => const Color(0xFF66BB6A), // green
    LegendRole.recon => const Color(0xFFAB47BC), // purple
    LegendRole.skirmisher => const Color(0xFFFFCA28), // yellow
    LegendRole.support => const Color(0xFF42A5F5), // blue
  };
}

class Legend {
  final int number;
  final String name;
  final LegendRole role;

  const Legend(this.number, this.name, this.role);
}

const List<Legend> kLegends = [
  Legend(1, 'Bloodhound', LegendRole.recon),
  Legend(2, 'Gibraltar', LegendRole.support),
  Legend(3, 'Lifeline', LegendRole.support),
  Legend(4, 'Pathfinder', LegendRole.skirmisher),
  Legend(5, 'Wraith', LegendRole.skirmisher),
  Legend(6, 'Bangalore', LegendRole.assault),
  Legend(7, 'Caustic', LegendRole.controller),
  Legend(8, 'Mirage', LegendRole.support),
  Legend(9, 'Octane', LegendRole.skirmisher),
  Legend(10, 'Wattson', LegendRole.controller),
  Legend(11, 'Crypto', LegendRole.recon),
  Legend(12, 'Revenant', LegendRole.skirmisher),
  Legend(13, 'Loba', LegendRole.support),
  Legend(14, 'Rampart', LegendRole.controller),
  Legend(15, 'Horizon', LegendRole.skirmisher),
  Legend(16, 'Fuse', LegendRole.assault),
  Legend(17, 'Valkyrie', LegendRole.skirmisher),
  Legend(18, 'Seer', LegendRole.recon),
  Legend(19, 'Ash', LegendRole.assault),
  Legend(20, 'Mad Maggie', LegendRole.assault),
  Legend(21, 'Newcastle', LegendRole.support),
  Legend(22, 'Vantage', LegendRole.recon),
  Legend(23, 'Catalyst', LegendRole.controller),
  Legend(24, 'Ballistic', LegendRole.assault),
  Legend(25, 'Conduit', LegendRole.support),
  Legend(26, 'Alter', LegendRole.skirmisher),
  Legend(27, 'Sparrow', LegendRole.recon),
  Legend(28, 'Axle', LegendRole.skirmisher),
];

final Map<String, Legend> kLegendsByName = {
  for (final l in kLegends) l.name.toLowerCase(): l,
};

/// A stable, case-insensitive grouping key for [name]: the canonical roster
/// name when known (case folded to match [kLegendsByName]), otherwise [name]
/// unchanged. Mirrors [canonicalMapKey] in `map_constants.dart` — what a
/// per-legend aggregate should group by, so a case variant upstream sends
/// for one player (e.g. `"bloodhound"` instead of `"Bloodhound"`) can't split
/// one legend into two identically-labelled rows. Never shown to the user —
/// display the [Legend.name] from [kLegendsByName], or the raw value, as
/// appropriate for the call site.
String canonicalLegendName(String name) =>
    kLegendsByName[name.toLowerCase()]?.name ?? name;

/// API name for the career-wide stats entry returned alongside per-legend stats.
const kCareerLegendName = 'Global';

String legendDisplayName(String name) =>
    name.toLowerCase() == kCareerLegendName.toLowerCase() ? 'Career' : name;
