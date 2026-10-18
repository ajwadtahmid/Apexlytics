import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/tracking/legend_stat_sort.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

LegendStat legend(
  String name, {
  int? kills,
  int? damage,
  int? wins,
  int? games,
}) => buildLegend(
  name: name,
  trackers: [
    if (kills != null)
      buildTracker(key: 'kills', displayName: 'BR Kills', value: kills),
    if (damage != null)
      buildTracker(key: 'damage', displayName: 'BR Damage', value: damage),
    if (wins != null)
      buildTracker(key: 'wins', displayName: 'BR Wins', value: wins),
    if (games != null)
      buildTracker(key: 'games', displayName: 'BR Games Played', value: games),
  ],
);

List<String> names(List<LegendStat> l) => [for (final x in l) x.name];

void main() {
  // Octane leads on every figure, then Wraith or Lifeline; Lifeline has no
  // damage reading and Bangalore nothing at all.
  final wraith = legend(
    'Wraith',
    kills: 100,
    damage: 20000,
    wins: 5,
    games: 50,
  );
  final octane = legend(
    'Octane',
    kills: 300,
    damage: 30000,
    wins: 20,
    games: 50,
  );
  final lifeline = legend('Lifeline', kills: 200, wins: 10, games: 200);
  final bangalore = legend('Bangalore');
  final all = [wraith, octane, lifeline, bangalore];

  test('kills, damage and wins put the biggest first', () {
    expect(names(sortLegendStats(all, LegendStatSort.kills)), [
      'Octane',
      'Lifeline',
      'Wraith',
      'Bangalore',
    ]);
    expect(names(sortLegendStats(all, LegendStatSort.damage)), [
      'Octane',
      'Wraith',
      'Lifeline',
      'Bangalore',
    ]);
    expect(names(sortLegendStats(all, LegendStatSort.wins)), [
      'Octane',
      'Lifeline',
      'Wraith',
      'Bangalore',
    ]);
  });

  test('a tie keeps the order the legends came in', () {
    final a = legend('Wraith', kills: 10);
    final b = legend('Octane', kills: 10);

    expect(names(sortLegendStats([a, b], LegendStatSort.kills)), [
      'Wraith',
      'Octane',
    ]);
    expect(
      names(sortLegendStats([b, a], LegendStatSort.kills, reversed: true)),
      ['Octane', 'Wraith'],
    );
  });

  test('recent follows the visit stack, then the rest as they came', () {
    final sorted = sortLegendStats(
      all,
      LegendStatSort.recent,
      recentStack: ['Octane', 'Wraith'],
    );

    expect(names(sorted), ['Octane', 'Wraith', 'Lifeline', 'Bangalore']);
    expect(
      names(
        sortLegendStats(
          all,
          LegendStatSort.recent,
          recentStack: ['Octane', 'Wraith'],
          reversed: true,
        ),
      ),
      ['Bangalore', 'Lifeline', 'Wraith', 'Octane'],
    );
  });

  test('recent with no visits leaves the order alone', () {
    expect(names(sortLegendStats(all, LegendStatSort.recent)), names(all));
  });

  test('role goes assault, skirmisher, support, and turns round', () {
    expect(names(sortLegendStats(all, LegendStatSort.role)), [
      'Bangalore',
      'Wraith',
      'Octane',
      'Lifeline',
    ]);
    expect(names(sortLegendStats(all, LegendStatSort.role, reversed: true)), [
      'Lifeline',
      'Octane',
      'Wraith',
      'Bangalore',
    ]);
  });

  test('the list passed in is left as it was', () {
    final before = names(all);

    sortLegendStats(all, LegendStatSort.kills);

    expect(names(all), before);
  });
}
