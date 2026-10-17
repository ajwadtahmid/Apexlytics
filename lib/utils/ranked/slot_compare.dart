import 'ranked_aggregates.dart';

/// One hour or weekday of play: its games and net RP.
typedef Slot = ({int slot, int games, int netRp});

List<Slot> hourSlots(List<HourBucket> buckets) => [
  for (final b in buckets) (slot: b.hourLocal, games: b.games, netRp: b.netRp),
];

List<Slot> weekdaySlots(List<WeekdayBucket> buckets) => [
  for (final b in buckets) (slot: b.weekday, games: b.games, netRp: b.netRp),
];

/// The hours to chart: the shortest run of consecutive hours, wrapping past
/// midnight if need be, that holds every one in [used]. Starts after the longest
/// stretch of unplayed hours, so a late-night player's axis isn't split in two.
List<int> hourAxis(Iterable<int> used) {
  final hours = used.toSet().toList()..sort();
  if (hours.isEmpty) return [for (var h = 0; h < 24; h++) h];
  var start = hours.first;
  var longestGap = -1;
  for (var i = 0; i < hours.length; i++) {
    final next = hours[(i + 1) % hours.length];
    // Unplayed hours between this one and the next, going round the clock.
    final gap = (next - hours[i] - 1 + 24) % 24;
    // A single played hour has the other 23 as its gap.
    final size = hours.length == 1 ? 23 : gap;
    if (size > longestGap) {
      longestGap = size;
      start = next;
    }
  }
  // No unplayed hour at all: the whole day, from midnight.
  if (longestGap == 0) start = 0;
  return [for (var i = 0; i < 24 - longestGap; i++) (start + i) % 24];
}

double _avg(Slot s) => s.netRp / s.games;

/// The slot with the highest (or, if [best] is false, lowest) RP per game among
/// those played at least [kMinGamesForInsight] times. Ties go to the one played
/// more, then the earlier.
Slot? bestSlot(List<Slot> slots, {bool best = true}) {
  Slot? pick;
  for (final s in slots) {
    if (s.games < kMinGamesForInsight) continue;
    if (pick == null) {
      pick = s;
      continue;
    }
    final c = _avg(s).compareTo(_avg(pick));
    final better = c != 0
        ? (best ? c > 0 : c < 0)
        : (s.games != pick.games ? s.games > pick.games : s.slot < pick.slot);
    if (better) pick = s;
  }
  return pick;
}

/// "Best hour moved from 9 PM to 11 PM", or "stayed" when it didn't. Null when
/// either side has no slot with enough games to name one.
String? slotVerdict({
  required String what,
  required String Function(int slot) label,
  required List<Slot> a,
  required List<Slot> b,
  required bool best,
}) {
  final x = bestSlot(a, best: best);
  final y = bestSlot(b, best: best);
  if (x == null || y == null) return null;
  final name = '${best ? 'Best' : 'Weakest'} $what';
  return x.slot == y.slot
      ? '$name stayed ${label(x.slot)}'
      : '$name moved from ${label(x.slot)} to ${label(y.slot)}';
}
