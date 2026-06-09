import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/player_stats.dart';

void main() {
  group('PlayerStats.fromJson', () {
    final validJson = {
      'global': {
        'name': 'TestPlayer',
        'uid': '123456',
        'level': 500,
        'rank': {'rankName': 'Gold', 'rankScore': 6000},
        'platform': 'PC',
      },
      'realtime': {'isOnline': 1, 'isInGame': 0},
      'legends': {
        'selected': {'LegendName': 'Wraith', 'data': []},
        'all': {},
      },
    };

    test('parses name from global block', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.name, 'TestPlayer');
    });

    test('parses uid as string', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.uid, '123456');
    });

    test('parses level correctly', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.level, 500);
    });

    test('parses rank name', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.rank, 'Gold');
    });

    test('parses rankScore', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.rankScore, 6000);
    });

    test('parses isOnline from numeric 1', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.isOnline, true);
    });

    test('parses isInGame from numeric 0', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.isInGame, false);
    });

    test('parses currentLegend', () {
      final stats = PlayerStats.fromJson(validJson);
      expect(stats.currentLegend, 'Wraith');
    });

    test('handles missing global block gracefully', () {
      final stats = PlayerStats.fromJson({});
      expect(stats.name, 'Unknown');
      expect(stats.level, 0);
      expect(stats.trackers, isEmpty);
    });

    test('parses boolean isOnline', () {
      final json = Map<String, dynamic>.from(validJson);
      json['realtime'] = {'isOnline': true, 'isInGame': false};
      final stats = PlayerStats.fromJson(json);
      expect(stats.isOnline, true);
    });

    test('handles missing rank block gracefully', () {
      final json = Map<String, dynamic>.from(validJson);
      json['global'] = Map<String, dynamic>.from(validJson['global'] as Map)
        ..remove('rank');
      final stats = PlayerStats.fromJson(json);
      expect(stats.rank, 'Unranked');
      expect(stats.rankScore, 0);
    });

    test('handles null uid and coerces to empty string', () {
      final json = Map<String, dynamic>.from(validJson);
      json['global'] = Map<String, dynamic>.from(validJson['global'] as Map)
        ..['uid'] = null;
      final stats = PlayerStats.fromJson(json);
      expect(stats.uid, '');
    });

    test('handles missing realtime block', () {
      final json = Map<String, dynamic>.from(validJson);
      json.remove('realtime');
      final stats = PlayerStats.fromJson(json);
      expect(stats.isOnline, false);
      expect(stats.isInGame, false);
    });

  });

  group('PlayerStats.presence', () {
    PlayerStats make({required bool isOnline, required bool isInGame}) =>
        PlayerStats(
          name: 'x', uid: '1', level: 1, rank: 'Gold', rankScore: 0,
          platform: 'PC', currentLegend: 'Wraith',
          isOnline: isOnline, isInGame: isInGame, trackers: [],
        );

    test('returns "In Game" when inGame', () {
      expect(make(isOnline: true, isInGame: true).presence, 'In Game');
    });
    test('returns "Online" when online but not in game', () {
      expect(make(isOnline: true, isInGame: false).presence, 'Online');
    });
    test('returns "Offline" when offline', () {
      expect(make(isOnline: false, isInGame: false).presence, 'Offline');
    });
  });

  group('LegendStat', () {
    test('killCount returns 0 when no kills tracker', () {
      final stat = const LegendStat(name: 'Wraith', trackers: []);
      expect(stat.killCount, 0);
    });

    test('killCount returns kills tracker value', () {
      const tracker = LegendTracker(key: 'kills', displayName: 'Kills', value: 500);
      const stat = LegendStat(name: 'Wraith', trackers: [tracker]);
      expect(stat.killCount, 500);
    });

    test('merge combines trackers', () {
      const base = LegendStat(
        name: 'Wraith',
        trackers: [LegendTracker(key: 'kills', displayName: 'Kills', value: 100)],
      );
      const incoming = LegendStat(
        name: 'Wraith',
        trackers: [
          LegendTracker(key: 'kills', displayName: 'Kills', value: 200),
          LegendTracker(key: 'wins', displayName: 'Wins', value: 50),
        ],
      );
      final merged = base.merge(incoming);
      expect(merged.trackers.length, 2);
      expect(merged.trackers.firstWhere((t) => t.key == 'kills').value, 200);
    });

    test('toJson / fromJson roundtrip preserves data', () {
      final stat = LegendStat(
        name: 'Bangalore',
        trackers: const [LegendTracker(key: 'kills', displayName: 'Kills', value: 999)],
        lastUpdated: DateTime(2024, 1, 1),
      );
      final json = stat.toJson();
      final restored = LegendStat.fromJson(json);
      expect(restored.name, 'Bangalore');
      expect(restored.trackers.first.value, 999);
      expect(restored.lastUpdated?.year, 2024);
    });
  });
}
