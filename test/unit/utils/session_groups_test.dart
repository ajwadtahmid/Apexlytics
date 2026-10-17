import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/ranked/session_groups.dart';
import 'package:flutter_test/flutter_test.dart';

RankedSession _session(DateTime start, {int netRp = 10}) => RankedSession(
  start: start,
  end: start.add(const Duration(minutes: 30)),
  games: 2,
  netRp: netRp,
  totalKills: 0,
  totalDamage: 0,
  killsGames: 0,
  damageGames: 0,
  matches: const [],
);

void main() {
  // A Wednesday, so this week began on Monday the 12th.
  final now = DateTime(2026, 10, 14, 15);

  List<String> labels(List<DateTime> starts) => [
    for (final g in groupSessions([
      for (final s in starts) _session(s),
    ], now: now))
      g.label,
  ];

  test('puts sessions under Today and Yesterday by their date', () {
    expect(
      labels([
        DateTime(2026, 10, 14, 23, 50),
        DateTime(2026, 10, 14, 1),
        DateTime(2026, 10, 13, 22),
      ]),
      ['Today', 'Yesterday'],
    );
  });

  test('the rest of this week, then last week, then each month', () {
    expect(
      labels([
        DateTime(2026, 10, 12, 20), // Monday: this week
        DateTime(2026, 10, 11, 20), // Sunday: last week
        DateTime(2026, 10, 5, 20), // last Monday
        DateTime(2026, 9, 27, 20), // the Sunday before: September
        DateTime(2026, 8, 3, 20),
      ]),
      ['This week', 'Last week', 'September 2026', 'August 2026'],
    );
  });

  test('on a Monday, yesterday is last week but still says Yesterday', () {
    final monday = DateTime(2026, 10, 12, 9);
    final groups = groupSessions([
      _session(DateTime(2026, 10, 11, 20)),
      _session(DateTime(2026, 10, 10, 20)),
    ], now: monday);

    expect(groups.map((g) => g.label), ['Yesterday', 'Last week']);
  });

  test('keeps the order it was given, one group per run', () {
    final groups = groupSessions([
      _session(DateTime(2026, 10, 14, 12)),
      _session(DateTime(2026, 10, 14, 8)),
      _session(DateTime(2026, 10, 13, 20)),
    ], now: now);

    expect(groups.map((g) => g.sessions.length), [2, 1]);
  });

  test('totals the RP of each group', () {
    final groups = groupSessions([
      _session(DateTime(2026, 10, 14, 12), netRp: 40),
      _session(DateTime(2026, 10, 14, 8), netRp: -15),
      _session(DateTime(2026, 10, 13, 20), netRp: 7),
    ], now: now);

    expect(groups.map((g) => g.netRp), [25, 7]);
  });

  test('is empty with no sessions', () {
    expect(groupSessions(const [], now: now), isEmpty);
  });
}
