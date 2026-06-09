import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/utils/storage/legend_stats_storage.dart';

import '../../helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loadLegendStats', () {
    test('returns empty list when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(loadLegendStats(prefs), isEmpty);
    });

    test('returns empty list on corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({'legend_stats': 'bad'});
      final prefs = await SharedPreferences.getInstance();
      expect(loadLegendStats(prefs), isEmpty);
    });
  });

  group('mergeLegendStats', () {
    test('adds new legends when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      final incoming = [buildLegend(name: 'Wraith')];
      final result = await mergeLegendStats(incoming, prefs);
      expect(result.length, 1);
      expect(result.first.name, 'Wraith');
    });

    test('returns stored list when incoming is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      final initial = [buildLegend(name: 'Wraith')];
      await mergeLegendStats(initial, prefs);
      final result = await mergeLegendStats([], prefs);
      expect(result.length, 1);
    });

    test('updates existing tracker values', () async {
      final prefs = await SharedPreferences.getInstance();
      const first = [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 100),
        ]),
      ];
      await mergeLegendStats(first, prefs);

      const second = [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 200),
        ]),
      ];
      final result = await mergeLegendStats(second, prefs);
      final kills = result.first.trackers.firstWhere((t) => t.key == 'kills');
      expect(kills.value, 200);
    });

    test('appends new trackers to an existing legend', () async {
      final prefs = await SharedPreferences.getInstance();
      await mergeLegendStats(const [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 100),
        ]),
      ], prefs);

      final result = await mergeLegendStats(const [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 100),
          LegendTracker(key: 'wins', displayName: 'Wins', value: 50),
        ]),
      ], prefs);

      expect(result.first.trackers.length, 2);
    });

    test('does not bump lastUpdated when trackers are unchanged', () async {
      final prefs = await SharedPreferences.getInstance();
      const legend = [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 100),
        ]),
      ];
      await mergeLegendStats(legend, prefs);
      // Load from prefs so both timestamps are at millisecond precision
      // (in-memory DateTime has microsecond precision; stored value does not).
      final firstUpdated = (loadLegendStats(prefs)).first.lastUpdated;

      await Future.delayed(const Duration(milliseconds: 5));
      await mergeLegendStats(legend, prefs);
      final secondUpdated = (loadLegendStats(prefs)).first.lastUpdated;
      expect(secondUpdated, firstUpdated);
    });

    test('bumps lastUpdated when tracker value changes', () async {
      final prefs = await SharedPreferences.getInstance();
      await mergeLegendStats(const [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 100),
        ]),
      ], prefs);
      final first = loadLegendStats(prefs);
      final firstUpdated = first.first.lastUpdated;

      await Future.delayed(const Duration(milliseconds: 5));
      await mergeLegendStats(const [
        LegendStat(name: 'Wraith', trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 200),
        ]),
      ], prefs);
      final second = loadLegendStats(prefs);
      expect(second.first.lastUpdated, isNot(firstUpdated));
    });

    test('adds entirely new legends alongside existing ones', () async {
      final prefs = await SharedPreferences.getInstance();
      await mergeLegendStats([buildLegend(name: 'Wraith')], prefs);
      final result = await mergeLegendStats([buildLegend(name: 'Lifeline')], prefs);
      expect(result.length, 2);
      expect(result.map((l) => l.name), containsAll(['Wraith', 'Lifeline']));
    });

    test('stores stats under uid-specific key', () async {
      final prefs = await SharedPreferences.getInstance();
      await mergeLegendStats([buildLegend(name: 'Wraith')], prefs, uid: 'abc');
      expect(loadLegendStats(prefs, uid: 'abc'), hasLength(1));
      expect(loadLegendStats(prefs), isEmpty);
    });
  });
}
