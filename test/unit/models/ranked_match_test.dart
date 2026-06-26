import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/ranked_match.dart';

void main() {
  // Mirrors a real BATTLE_ROYALE row from /games (ZZephyrous sample).
  Map<String, dynamic> brMatch() => {
        'uid': '1006838015507',
        'name': 'ZZephyrous',
        'legendPlayed': 'Axle',
        'gameMode': 'BATTLE_ROYALE',
        'gameLengthSecs': 926,
        'gameStartTimestamp': 1782093420,
        'gameEndTimestamp': 1782094346,
        'gameData': [
          {'key': 'kills', 'value': 3, 'name': 'BR Kills'},
          {'key': 'damage', 'value': 1387, 'name': 'BR Damage'},
          {'key': 'axle_tactical', 'value': 13, 'name': 'Tactical: Nitro Gates Used'},
        ],
        'BRScoreChange': 44,
        'BRScore': 12203,
        'BRRankImg': 'https://api.mozambiquehe.re/assets/ranks/diamond4.png',
        'isPartyFull': false,
        'map': 'broken_moon_rotation',
      };

  group('RankedMatch.fromJson', () {
    test('parses core fields', () {
      final m = RankedMatch.fromJson(brMatch());
      expect(m.uid, '1006838015507');
      expect(m.playerName, 'ZZephyrous');
      expect(m.legend, 'Axle');
      expect(m.gameMode, 'BATTLE_ROYALE');
      expect(m.mapKey, 'broken_moon_rotation');
      expect(m.rpChange, 44);
      expect(m.cumulativeRp, 12203);
      expect(m.lengthSecs, 926);
      expect(m.isPartyFull, false);
    });

    test('parses timestamps as UTC epoch seconds', () {
      final m = RankedMatch.fromJson(brMatch());
      expect(m.startTime.isUtc, true);
      expect(m.startTime.millisecondsSinceEpoch, 1782093420 * 1000);
      expect(m.endTime.millisecondsSinceEpoch, 1782094346 * 1000);
    });

    test('normalizes trackers and exposes kills/damage by name', () {
      final m = RankedMatch.fromJson(brMatch());
      expect(m.trackers.length, 3);
      expect(m.kills, 3);
      expect(m.damage, 1387);
      expect(m.trackerValue('Tactical: Nitro Gates Used'), 13);
    });

    test('matches trackers by name even when the key differs', () {
      // Another player carries the same stat under a different key.
      final json = brMatch()
        ..['gameData'] = [
          {'key': 'specialEvent_kills', 'value': 5, 'name': 'BR Kills'},
          {'key': 'specialEvent_damage', 'value': 2000, 'name': 'BR Damage'},
        ];
      final m = RankedMatch.fromJson(json);
      expect(m.kills, 5);
      expect(m.damage, 2000);
    });

    test('skips empty/placeholder tracker rows', () {
      final json = brMatch()
        ..['gameData'] = [
          {'key': 'kills', 'value': 1, 'name': 'BR Kills'},
          {'key': 'empty', 'value': 0, 'name': ''},
        ];
      final m = RankedMatch.fromJson(json);
      expect(m.trackers.length, 1);
    });

    test('isRanked requires BR mode AND RP movement', () {
      expect(RankedMatch.fromJson(brMatch()).isRanked, true);

      // UNKNOWN mode is never ranked.
      final unknown = brMatch()..['gameMode'] = 'UNKNOWN';
      expect(RankedMatch.fromJson(unknown).isRanked, false);

      // A BR match with no RP change is a pub — BR but not ranked.
      final pub = brMatch()..['BRScoreChange'] = 0;
      final pubMatch = RankedMatch.fromJson(pub);
      expect(pubMatch.isBattleRoyale, true);
      expect(pubMatch.isRanked, false);
    });

    test('tolerates missing fields without throwing', () {
      final m = RankedMatch.fromJson({});
      expect(m.legend, 'Unknown');
      expect(m.gameMode, 'UNKNOWN');
      expect(m.mapKey, 'UNKNOWN');
      expect(m.kills, 0);
      expect(m.trackers, isEmpty);
    });

    test('listFromJson skips non-map entries', () {
      final list = RankedMatch.listFromJson([brMatch(), 'garbage', 42]);
      expect(list.length, 1);
    });
  });

  group('storage serialization', () {
    test('dedupKey is uid + start second', () {
      final m = RankedMatch.fromJson(brMatch());
      expect(m.dedupKey, '1006838015507_1782093420');
    });

    test('toStoredMap/fromStoredMap round-trips all fields', () {
      final orig = RankedMatch.fromJson(brMatch());
      final restored = RankedMatch.fromStoredMap(orig.toStoredMap());

      expect(restored.uid, orig.uid);
      expect(restored.playerName, orig.playerName);
      expect(restored.legend, orig.legend);
      expect(restored.gameMode, orig.gameMode);
      expect(restored.mapKey, orig.mapKey);
      expect(restored.rpChange, orig.rpChange);
      expect(restored.cumulativeRp, orig.cumulativeRp);
      expect(restored.lengthSecs, orig.lengthSecs);
      expect(restored.startTime, orig.startTime);
      expect(restored.endTime, orig.endTime);
      expect(restored.isPartyFull, orig.isPartyFull);
      expect(restored.kills, orig.kills);
      expect(restored.damage, orig.damage);
      expect(restored.trackers.length, orig.trackers.length);
      expect(
        restored.trackerValue('Tactical: Nitro Gates Used'),
        orig.trackerValue('Tactical: Nitro Gates Used'),
      );
    });
  });
}
