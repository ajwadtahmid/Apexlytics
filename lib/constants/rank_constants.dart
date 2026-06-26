import 'dart:ui';

class RankDivision {
  final String tier;
  final String? division;
  final int rp;
  final Color color;

  const RankDivision(this.tier, this.division, this.rp, this.color);

  String get label => division != null ? '$tier $division' : tier;

  String get assetPath =>
      'assets/ranks/${tier.toLowerCase().replaceAll(' ', '_')}.webp';
}

const kRookieColor = Color(0xFF616161);
const kBronzeColor = Color(0xFFCD853F);
const kSilverColor = Color(0xFFB0BEC5);
const kGoldColor = Color(0xFFFFD54F);
const kPlatinumColor = Color(0xFF26C6DA);
const kDiamondColor = Color(0xFF7986CB);
const kMasterColor = Color(0xFFAB47BC);

const kPredatorColor = Color(0xFFFF4500);
const kApexPredatorRank = 'Apex Predator';

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
