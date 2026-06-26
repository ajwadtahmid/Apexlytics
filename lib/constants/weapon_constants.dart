enum WeaponType {
  assaultRifle,
  smg,
  lmg,
  sniper,
  shotgun,
  marksman,
  pistol;

  String get displayName => switch (this) {
    WeaponType.assaultRifle => 'Assault Rifle',
    WeaponType.smg => 'SMG',
    WeaponType.lmg => 'LMG',
    WeaponType.sniper => 'Sniper Rifle',
    WeaponType.shotgun => 'Shotgun',
    WeaponType.marksman => 'Marksman',
    WeaponType.pistol => 'Pistol',
  };
}

class Weapon {
  final String name;
  final String fullName;
  final WeaponType type;
  final List<String> altNames;
  final String? _assetFileOverride;

  const Weapon({
    required this.name,
    required this.fullName,
    required this.type,
    this.altNames = const [],
    String? assetFileName,
  }) : _assetFileOverride = assetFileName;

  String get assetPath => 'assets/weapons/${_assetFileOverride ?? _assetName()}.webp';

  String _assetName() => name
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '')
      .replaceAll('.', '');
}

// ── Assault Rifles ────────────────────────────────────────────────────────

const Weapon r301 = Weapon(
  name: 'R-301',
  fullName: 'R-301 Carbine',
  type: WeaponType.assaultRifle,
  altNames: ['R301'],
);

const Weapon havoc = Weapon(
  name: 'HAVOC',
  fullName: 'HAVOC Rifle',
  type: WeaponType.assaultRifle,
);

const Weapon flatline = Weapon(
  name: 'Flatline',
  fullName: 'VK-47 Flatline',
  type: WeaponType.assaultRifle,
  altNames: ['VK-47'],
);

const Weapon hemlok = Weapon(
  name: 'Hemlok',
  fullName: 'Hemlok Burst AR',
  type: WeaponType.assaultRifle,
);

const Weapon nemesis = Weapon(
  name: 'Nemesis',
  fullName: 'Nemesis Burst AR',
  type: WeaponType.assaultRifle,
);

// ── Submachine Guns ───────────────────────────────────────────────────────

const Weapon alternator = Weapon(
  name: 'Alternator',
  fullName: 'Alternator SMG',
  type: WeaponType.smg,
);

const Weapon r99 = Weapon(
  name: 'R-99',
  fullName: 'R-99 SMG',
  type: WeaponType.smg,
  altNames: ['R99'],
);

const Weapon prowler = Weapon(
  name: 'Prowler',
  fullName: 'Prowler Burst PDW',
  type: WeaponType.smg,
);

const Weapon volt = Weapon(
  name: 'Volt',
  fullName: 'Volt SMG',
  type: WeaponType.smg,
);

const Weapon car = Weapon(
  name: 'C.A.R.',
  fullName: 'C.A.R. SMG',
  type: WeaponType.smg,
  altNames: ['CAR'],
);

// ── Light Machine Guns ────────────────────────────────────────────────────

const Weapon devotion = Weapon(
  name: 'Devotion',
  fullName: 'Devotion LMG',
  type: WeaponType.lmg,
);

const Weapon lstar = Weapon(
  name: 'L-STAR',
  fullName: 'L-STAR EMG',
  type: WeaponType.lmg,
);

const Weapon spitfire = Weapon(
  name: 'Spitfire',
  fullName: 'M600 Spitfire',
  type: WeaponType.lmg,
  altNames: ['M600'],
);

const Weapon rampage = Weapon(
  name: 'Rampage',
  fullName: 'Rampage LMG',
  type: WeaponType.lmg,
);

// ── Sniper Rifles ─────────────────────────────────────────────────────────

const Weapon longbow = Weapon(
  name: 'Longbow',
  fullName: 'Longbow DMR',
  type: WeaponType.sniper,
);

const Weapon chargeRifle = Weapon(
  name: 'Charge Rifle',
  fullName: 'Charge Rifle',
  type: WeaponType.sniper,
);

const Weapon sentinel = Weapon(
  name: 'Sentinel',
  fullName: 'Sentinel',
  type: WeaponType.sniper,
);

const Weapon kraber = Weapon(
  name: 'Kraber',
  fullName: 'Kraber .50-Cal',
  type: WeaponType.sniper,
);

// ── Shotguns ──────────────────────────────────────────────────────────────

const Weapon eva8 = Weapon(
  name: 'EVA-8',
  fullName: 'EVA-8 Auto',
  type: WeaponType.shotgun,
);

const Weapon mastiff = Weapon(
  name: 'Mastiff',
  fullName: 'Mastiff',
  type: WeaponType.shotgun,
);

const Weapon mozambique = Weapon(
  name: 'Mozambique',
  fullName: 'Mozambique',
  type: WeaponType.shotgun,
);

const Weapon peacekeeper = Weapon(
  name: 'Peacekeeper',
  fullName: 'Peacekeeper',
  type: WeaponType.shotgun,
);

// ── Marksman Weapons ──────────────────────────────────────────────────────

const Weapon g7 = Weapon(
  name: 'G7 Scout',
  fullName: 'G7 Scout',
  type: WeaponType.marksman,
  altNames: ['G7'],
  assetFileName: 'g7',
);

const Weapon repeater30 = Weapon(
  name: '30-30 Repeater',
  fullName: '30-30 Repeater',
  type: WeaponType.marksman,
  altNames: ['30-30'],
  assetFileName: 'repeater_30',
);

const Weapon tripleTake = Weapon(
  name: 'Triple Take',
  fullName: 'Triple Take',
  type: WeaponType.marksman,
);

const Weapon bocek = Weapon(
  name: 'Bocek',
  fullName: 'Bocek Compound Bow',
  type: WeaponType.marksman,
  altNames: ['Bow'],
);

// ── Pistols ───────────────────────────────────────────────────────────────

const Weapon p2020 = Weapon(
  name: 'P2020',
  fullName: 'P2020',
  type: WeaponType.pistol,
);

const Weapon re45 = Weapon(
  name: 'RE-45',
  fullName: 'RE-45 Auto',
  type: WeaponType.pistol,
);

const Weapon wingman = Weapon(
  name: 'Wingman',
  fullName: 'Wingman',
  type: WeaponType.pistol,
);

// ── Weapon lookup maps ────────────────────────────────────────────────────

const List<Weapon> kAllWeapons = [
  // Assault Rifles
  r301, havoc, flatline, hemlok, nemesis,
  // SMGs
  alternator, r99, prowler, volt, car,
  // LMGs
  devotion, lstar, spitfire, rampage,
  // Snipers
  longbow, chargeRifle, sentinel, kraber,
  // Shotguns
  eva8, mastiff, mozambique, peacekeeper,
  // Marksman
  g7, repeater30, tripleTake, bocek,
  // Pistols
  p2020, re45, wingman,
];

final Map<String, Weapon> kWeaponsByName = {
  for (final w in kAllWeapons) w.name.toLowerCase(): w,
  for (final w in kAllWeapons) w.fullName.toLowerCase(): w,
  for (final w in kAllWeapons)
    for (final alt in w.altNames) alt.toLowerCase(): w,
};

List<Weapon> _byType(WeaponType t) =>
    kAllWeapons.where((w) => w.type == t).toList();

final Map<WeaponType, List<Weapon>> kWeaponsByType = {
  WeaponType.assaultRifle: _byType(WeaponType.assaultRifle),
  WeaponType.smg: _byType(WeaponType.smg),
  WeaponType.lmg: _byType(WeaponType.lmg),
  WeaponType.sniper: _byType(WeaponType.sniper),
  WeaponType.shotgun: _byType(WeaponType.shotgun),
  WeaponType.marksman: _byType(WeaponType.marksman),
  WeaponType.pistol: _byType(WeaponType.pistol),
};

/// Look up a weapon by name, full name, or alt name (case-insensitive).
Weapon? findWeapon(String query) {
  return kWeaponsByName[query.toLowerCase()];
}
