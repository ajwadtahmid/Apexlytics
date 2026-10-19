import 'dart:ui';

class RankDivision {
  final String tier;
  final String? division;
  final int rp;
  final Color color;

  const RankDivision(this.tier, this.division, this.rp, this.color);

  String get label => division != null ? '$tier $division' : tier;

  /// The bundled badge for this rung, or null when none is bundled (Rookie).
  /// Callers show no badge for null; they don't each pick their own stand-in.
  /// A tier with divisions shows its own division's badge; Master has none.
  String? get assetPath =>
      rankBadgePath(tier.toLowerCase(), division: _divisionNumbers[division]);
}

const _divisionNumbers = {'I': 1, 'II': 2, 'III': 3, 'IV': 4};

/// Tiers with badge art in `assets/ranks/<tier>.webp`. Rookie has none.
const kBundledRankTiers = {
  'bronze',
  'silver',
  'gold',
  'platinum',
  'diamond',
  'master',
};

/// Tiers whose badges carry the division, in `assets/ranks/<tier>_<n>.webp`.
/// Master has a single badge, and Apex Predator sits outside the ladder.
const kDivisionBadgeTiers = {'bronze', 'silver', 'gold', 'platinum', 'diamond'};

/// The bundled badge for [tier] (lower case, e.g. `platinum`) at [division]
/// 1–4, or null for a tier with no art. A tier with divisions falls back to its
/// plain badge when the division is missing or out of range.
String? rankBadgePath(String tier, {int? division}) {
  if (!kBundledRankTiers.contains(tier)) return null;
  final divided =
      kDivisionBadgeTiers.contains(tier) &&
      division != null &&
      division >= 1 &&
      division <= 4;
  return divided
      ? 'assets/ranks/${tier}_$division.webp'
      : 'assets/ranks/$tier.webp';
}

/// The Apex Predator badge, which sits outside the ladder.
const kPredatorBadgeAsset = 'assets/ranks/apex_predator.webp';

const kRookieColor = Color(0xFF616161);
const kBronzeColor = Color(0xFFCD853F);
const kSilverColor = Color(0xFFB0BEC5);
const kGoldColor = Color(0xFFFFD54F);
const kPlatinumColor = Color(0xFF26C6DA);
const kDiamondColor = Color(0xFF7986CB);
const kMasterColor = Color(0xFFAB47BC);

const kPredatorColor = Color(0xFFFF4500);
const kApexPredatorRank = 'Apex Predator';

/// The one place that decides which colour a rank is shown in: Apex
/// Predator's own colour, otherwise [division]'s. Rank colours are defined
/// above and nowhere else; read them through this (or `kRankLadder`), don't
/// copy the values.
Color rankDisplayColor(RankDivision division, {bool isPredator = false}) =>
    isPredator ? kPredatorColor : division.color;

const List<RankDivision> kRankLadder = [
  RankDivision('Rookie', 'IV', 0, kRookieColor),
  RankDivision('Rookie', 'III', 250, kRookieColor),
  RankDivision('Rookie', 'II', 500, kRookieColor),
  RankDivision('Rookie', 'I', 750, kRookieColor),
  RankDivision('Bronze', 'IV', 1000, kBronzeColor),
  RankDivision('Bronze', 'III', 1500, kBronzeColor),
  RankDivision('Bronze', 'II', 2000, kBronzeColor),
  RankDivision('Bronze', 'I', 2500, kBronzeColor),
  RankDivision('Silver', 'IV', 3000, kSilverColor),
  RankDivision('Silver', 'III', 3500, kSilverColor),
  RankDivision('Silver', 'II', 4000, kSilverColor),
  RankDivision('Silver', 'I', 4750, kSilverColor),
  RankDivision('Gold', 'IV', 5500, kGoldColor),
  RankDivision('Gold', 'III', 6250, kGoldColor),
  RankDivision('Gold', 'II', 7000, kGoldColor),
  RankDivision('Gold', 'I', 7750, kGoldColor),
  RankDivision('Platinum', 'IV', 8500, kPlatinumColor),
  RankDivision('Platinum', 'III', 9250, kPlatinumColor),
  RankDivision('Platinum', 'II', 10000, kPlatinumColor),
  RankDivision('Platinum', 'I', 11000, kPlatinumColor),
  RankDivision('Diamond', 'IV', 12000, kDiamondColor),
  RankDivision('Diamond', 'III', 13000, kDiamondColor),
  RankDivision('Diamond', 'II', 14000, kDiamondColor),
  RankDivision('Diamond', 'I', 15000, kDiamondColor),
  RankDivision('Master', null, 16000, kMasterColor),
];
