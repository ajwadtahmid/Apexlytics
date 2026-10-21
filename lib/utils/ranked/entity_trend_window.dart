/// How many of a legend's or map's newest games count as "recent" when its
/// trend is worked out, for the window the player has chosen.
///
/// Games, not sessions: games are the sample, and a legend played hundreds of
/// times and one tried a dozen times need different windows to read the same.
library;

import 'dart:math' as math;

import '../../models/ranked_match.dart';
import 'ranked_aggregates.dart';

/// Saved in place of a game count to mean "pick it for me".
const int kEntityTrendAuto = 0;

/// Counts offered as shortcuts. Any count from [kTrendCustomMin] to
/// [kTrendCustomMax] can be typed in as well.
const List<int> kEntityTrendPresets = [10, 25, 50, 100];

/// The fewest and the most games a window typed in can be. How many an entity
/// can actually use is limited again by its own games (see [maxTrendWindow]).
const int kTrendCustomMin = 5;
const int kTrendCustomMax = 1000;

/// What Auto picks: about [kAutoTrendShare] of the games, but never fewer than
/// [kAutoTrendMinGames] nor more than [kAutoTrendMaxGames]. So a legend with 35
/// games compares its last 9 with the rest, and one with 1,500 its last 100.
const double kAutoTrendShare = 0.25;
const int kAutoTrendMinGames = 5;
const int kAutoTrendMaxGames = 100;

/// Whether [choice] can be a saved window: Auto, or a count in range.
bool isTrendChoice(int choice) =>
    choice == kEntityTrendAuto ||
    (choice >= kTrendCustomMin && choice <= kTrendCustomMax);

/// The biggest window an entity with [games] games can have: half of them, so
/// the recent games are never most of the history, and no more than
/// [kTrendCustomMax].
int maxTrendWindow(int games) => math.min(kTrendCustomMax, games ~/ 2);

/// How many of an entity's newest games are "recent".
typedef EntityTrendWindow = ({int recent});

/// The window for an entity with [games] games under [choice]: how many of the
/// newest are "recent".
///
/// A chosen count is used as it is, unless that would be more than half the
/// games (see [maxTrendWindow]), when half is used. Null with fewer than
/// `kAutoTrendMinGames * 2` games, where there is nothing to compare against.
EntityTrendWindow? resolveEntityTrendWindow(int choice, int games) {
  if (games < kAutoTrendMinGames * 2) return null;
  if (choice != kEntityTrendAuto) {
    return (recent: math.min(choice, maxTrendWindow(games)));
  }
  return (
    recent: (games * kAutoTrendShare).round().clamp(
      kAutoTrendMinGames,
      kAutoTrendMaxGames,
    ),
  );
}

/// What an entity's trend lines show, and the window they were worked out
/// over; no window, and so nothing to show, with too few games.
typedef EntityTrendReading = ({EntityTrends trends, EntityTrendWindow? window});

/// [matches] (one legend's or one map's) and their trends under [choice].
EntityTrendReading entityTrendReading(List<RankedMatch> matches, int choice) {
  final window = resolveEntityTrendWindow(choice, matches.length);
  return (
    trends: window == null
        ? (rp: null, kills: null, damage: null)
        : entityTrends(matches, recentGames: window.recent),
    window: window,
  );
}

/// Remembers the last [entityTrendReading], for a sheet that asks for it on every
/// rebuild: the games are sorted and averaged again only when they, or the
/// window, have changed.
class EntityTrendReadingCache {
  List<RankedMatch>? _matches;
  int? _choice;
  EntityTrendReading? _reading;

  EntityTrendReading read(List<RankedMatch> matches, int choice) {
    final cached = _reading;
    if (cached != null && identical(matches, _matches) && choice == _choice) {
      return cached;
    }
    _matches = matches;
    _choice = choice;
    return _reading = entityTrendReading(matches, choice);
  }
}
