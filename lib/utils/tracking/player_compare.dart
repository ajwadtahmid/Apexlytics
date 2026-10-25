import '../../constants/legend_constants.dart' show legendDisplayName;
import '../../constants/rank_constants.dart';
import '../../constants/tracker_constants.dart';
import '../../models/player_stats.dart';
import '../../models/rank_info.dart';
import '../formatting/format.dart'
    show formatNumber, formatNumberOrNone, kNoReading;
import '../formatting/rank_utils.dart' show rankIndex;
import '../formatting/tracker_utils.dart'
    show deduplicateTrackers, trackerValueMap;
import '../ranked/ranked_tally.dart' show kMinGamesForInsight;
import 'legend_calculations.dart';

/// One row of a head-to-head between the reader (the first side, "you") and
/// another player, before it is drawn.
class CompareLine {
  final String label;
  final String valueA;
  final String valueB;

  /// The reader's figure minus the other player's. Null when the row says
  /// nothing about who is ahead (a missing figure, or two different tiers).
  final double? delta;
  final bool integerDelta;

  /// How many decimals the change shows when it is not a whole count.
  final int decimals;

  /// True where a lower figure is better.
  final bool invert;

  const CompareLine(
    this.label,
    this.valueA,
    this.valueB, {
    this.delta,
    this.integerDelta = false,
    this.decimals = 1,
    this.invert = false,
  });
}

/// Where a player sits above the bottom of the ladder, with Apex Predator one
/// step over the top rung, which Master shares with it by RP alone.
int _ladderPosition(PlayerStats s) =>
    s.rank == kApexPredatorRank ? kRankLadder.length : rankIndex(s.rankScore);

/// The ranked rows: rank (with the gap in divisions, since RP gaps mean
/// different things on different rungs), RP, and what is left to the next
/// rank.
List<CompareLine> rankedCompareLines(PlayerStats me, PlayerStats them) {
  final mine = RankInfo.from(me);
  final theirs = RankInfo.from(them);
  final sameTier =
      mine.tier != null &&
      theirs.tier != null &&
      mine.tier == theirs.tier &&
      mine.rpToNext != null &&
      theirs.rpToNext != null;

  return [
    CompareLine(
      'Rank',
      mine.label,
      theirs.label,
      delta: (_ladderPosition(me) - _ladderPosition(them)).toDouble(),
      integerDelta: true,
    ),
    CompareLine(
      'RP',
      formatNumber(me.rankScore),
      formatNumber(them.rankScore),
      delta: (me.rankScore - them.rankScore).toDouble(),
      integerDelta: true,
    ),
    if (mine.nextLabel != null || theirs.nextLabel != null)
      CompareLine(
        'Next rank',
        mine.nextLabel ?? kNoReading,
        theirs.nextLabel ?? kNoReading,
      ),
    if (mine.rpToNext != null || theirs.rpToNext != null)
      CompareLine(
        'RP needed',
        mine.rpToNext == null ? kNoReading : formatNumber(mine.rpToNext!),
        theirs.rpToNext == null ? kNoReading : formatNumber(theirs.rpToNext!),
        // Only within one tier, whose divisions are all the same width.
        delta: sameTier ? (mine.rpToNext! - theirs.rpToNext!).toDouble() : null,
        integerDelta: true,
        invert: true,
      ),
  ];
}

LegendStat? _legendOf(PlayerStats p, String name) {
  for (final l in p.legendStats) {
    if (l.name == name) return l;
  }
  return null;
}

/// Games played on a legend, from its trackers; null when it does not say.
int? _gamesOn(LegendStat? legend) => legend == null
    ? null
    : trackerValueMap(legend.trackers)[TrackerKeys.brGamesPlayed];

/// The legends either player has stats for, the ones both have first and among
/// those the one with the most games on the thinner side first, since that is
/// the comparison with the most behind it. Then the rest, by name.
List<String> comparableLegends(PlayerStats me, PlayerStats them) {
  final names = <String>{
    for (final l in me.legendStats)
      if (l.trackers.isNotEmpty) l.name,
    for (final l in them.legendStats)
      if (l.trackers.isNotEmpty) l.name,
  };
  bool shared(String n) =>
      (_legendOf(me, n)?.trackers.isNotEmpty ?? false) &&
      (_legendOf(them, n)?.trackers.isNotEmpty ?? false);
  int thinner(String n) {
    final a = _gamesOn(_legendOf(me, n)) ?? 0;
    final b = _gamesOn(_legendOf(them, n)) ?? 0;
    return a < b ? a : b;
  }

  final list = names.toList()
    ..sort((x, y) {
      final sx = shared(x), sy = shared(y);
      if (sx != sy) return sx ? -1 : 1;
      if (sx) {
        final c = thinner(y).compareTo(thinner(x));
        if (c != 0) return c;
      }
      return legendDisplayName(x).compareTo(legendDisplayName(y));
    });
  return list;
}

/// A legend in the picker, with how much each player has on it.
class LegendOption {
  final String name;
  final int? gamesA;
  final int? gamesB;

  /// Both players have stats for it.
  final bool shared;

  const LegendOption(
    this.name, {
    this.gamesA,
    this.gamesB,
    this.shared = false,
  });
}

/// [comparableLegends], with each legend's game counts for the picker.
List<LegendOption> legendOptions(PlayerStats me, PlayerStats them) => [
  for (final name in comparableLegends(me, them))
    LegendOption(
      name,
      gamesA: _gamesOn(_legendOf(me, name)),
      gamesB: _gamesOn(_legendOf(them, name)),
      shared:
          (_legendOf(me, name)?.trackers.isNotEmpty ?? false) &&
          (_legendOf(them, name)?.trackers.isNotEmpty ?? false),
    ),
];

/// One legend, compared: the trackers each player has on it, as the game
/// reports them, and what can be worked out from them (the per-game rates,
/// which do not depend on who has played more).
class LegendCompare {
  final List<CompareLine> trackers;
  final List<CompareLine> calculated;
  final int? gamesA;
  final int? gamesB;

  /// When each side's figures were last updated, if known.
  final DateTime? updatedA;
  final DateTime? updatedB;

  const LegendCompare({
    required this.trackers,
    required this.calculated,
    this.gamesA,
    this.gamesB,
    this.updatedA,
    this.updatedB,
  });

  bool get isEmpty => trackers.isEmpty && calculated.isEmpty;

  /// Either side has too few games on the legend for a rate to mean much.
  bool get lowSample =>
      (gamesA != null && gamesA! < kMinGamesForInsight) ||
      (gamesB != null && gamesB! < kMinGamesForInsight);
}

/// Trackers shown first, in this order; the rest follow by name.
const _trackerOrder = [
  TrackerKeys.brGamesPlayed,
  TrackerKeys.brKills,
  TrackerKeys.brDamage,
  TrackerKeys.brWins,
];

Map<String, ({String name, int value})> _trackersByName(
  List<LegendTracker> trackers,
) => {
  for (final t in deduplicateTrackers(trackers))
    t.displayName.toLowerCase(): (name: t.displayName, value: t.value),
};

LegendCompare legendCompare(
  PlayerStats me,
  PlayerStats them,
  String legendName,
) {
  final mine = _legendOf(me, legendName);
  final theirs = _legendOf(them, legendName);
  final myTrackers = mine?.trackers ?? const <LegendTracker>[];
  final theirTrackers = theirs?.trackers ?? const <LegendTracker>[];

  final myByName = _trackersByName(myTrackers);
  final theirByName = _trackersByName(theirTrackers);
  int order(String k) {
    final i = _trackerOrder.indexOf(k);
    return i < 0 ? _trackerOrder.length : i;
  }

  final keys = <String>{...myByName.keys, ...theirByName.keys}.toList()
    ..sort((x, y) {
      final c = order(x).compareTo(order(y));
      return c != 0 ? c : x.compareTo(y);
    });
  final trackers = [
    for (final key in keys)
      CompareLine(
        (myByName[key] ?? theirByName[key])!.name,
        formatNumberOrNone(myByName[key]?.value),
        formatNumberOrNone(theirByName[key]?.value),
        // Games played says why the totals differ, not who is better.
        delta:
            key != TrackerKeys.brGamesPlayed &&
                myByName[key] != null &&
                theirByName[key] != null
            ? (myByName[key]!.value - theirByName[key]!.value).toDouble()
            : null,
        integerDelta: true,
      ),
  ];

  final myRates = {for (final r in legendRates(myTrackers)) r.label: r};
  final theirRates = {for (final r in legendRates(theirTrackers)) r.label: r};
  final rateLabels = <String>{...myRates.keys, ...theirRates.keys};
  final calculated = [
    for (final label in rateLabels)
      CompareLine(
        label,
        myRates[label]?.text ?? kNoReading,
        theirRates[label]?.text ?? kNoReading,
        delta: myRates[label] != null && theirRates[label] != null
            ? myRates[label]!.value - theirRates[label]!.value
            : null,
        integerDelta: label == 'Damage per Kill',
        // Revives per game move in hundredths.
        decimals: label == 'Revive Rate' ? 2 : 1,
      ),
  ];

  return LegendCompare(
    trackers: trackers,
    calculated: calculated,
    gamesA: _gamesOn(mine),
    gamesB: _gamesOn(theirs),
    updatedA: mine?.lastUpdated,
    updatedB: theirs?.lastUpdated,
  );
}
