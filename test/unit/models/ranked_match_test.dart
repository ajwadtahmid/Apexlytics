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
      {
        'key': 'axle_tactical',
        'value': 13,
        'name': 'Tactical: Nitro Gates Used',
      },
    ],
    'BRScoreChange': 44,
    'BRScore': 12203,
    'BRRankImg': 'https://api.apexlegendsstatus.com/assets/ranks/diamond4.png',
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
      // No tracker means "not reported", which is not a scoreless game.
      expect(m.kills, isNull);
      expect(m.damage, isNull);
      expect(m.trackers, isEmpty);
    });

    test('listFromJson skips non-map entries', () {
      final list = RankedMatch.listFromJson([brMatch(), 'garbage', 42]);
      expect(list.length, 1);
    });

    test('listFromJson skips a map row with a wrongly-typed field, keeping '
        'the rest of the batch', () {
      final list = RankedMatch.listFromJson([
        brMatch(),
        {...brMatch(), 'isPartyFull': 0},
        {...brMatch(), 'name': 12345},
        brMatch(),
      ]);
      expect(list.length, 2);
    });

    test('listFromJson skips a match with no start timestamp, which would '
        'otherwise all key as uid_0', () {
      final noStart = {...brMatch()}..remove('gameStartTimestamp');
      final list = RankedMatch.listFromJson([noStart, brMatch(), noStart]);
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
      // Not part of toStoredMap() — the history store manages this column
      // separately (upgrade-only) — so a plain round-trip leaves it unset.
      expect(restored.seasonId, isNull);
    });

    test('fromStoredMap reads season_id back from a persisted row', () {
      final row = RankedMatch.fromJson(brMatch()).toStoredMap();
      row['season_id'] = 'br_ranked_s29_s2';
      expect(RankedMatch.fromStoredMap(row).seasonId, 'br_ranked_s29_s2');
    });

    test('fromStoredMap tolerates a corrupt trackers blob (no throw)', () {
      // A hand-edited / foreign backup imported verbatim could carry malformed
      // JSON here; hydrating it must degrade to no trackers, not crash the read.
      final row = RankedMatch.fromJson(brMatch()).toStoredMap();
      row['trackers'] = '{not valid json';
      final restored = RankedMatch.fromStoredMap(row);
      expect(restored.trackers, isEmpty);
      // kills/damage live in their own columns, so they survive a blob that
      // can no longer be parsed.
      expect(restored.kills, 3);
      expect(restored.damage, 1387);
      expect(restored.legend, 'Axle'); // the rest of the row still hydrates
    });

    test('a stored row writes its trackers blob back exactly as read', () {
      // The blob is kept raw and only decoded if something reads trackers,
      // so re-storing a hydrated row (e.g. after an edit) must not rewrite it.
      final row = RankedMatch.fromJson(brMatch()).toStoredMap();
      const blob = '[{"key":"kills","name":"BR Kills","value":3}]';
      row['trackers'] = blob;

      final restored = RankedMatch.fromStoredMap(row);
      expect(restored.toStoredMap()['trackers'], blob);
      expect(restored.withEdits({'kills': 5}).toStoredMap()['trackers'], blob);
      expect(restored.withEditsCleared().toStoredMap()['trackers'], blob);
    });

    test('a stored row still decodes its trackers when they are read', () {
      final restored = RankedMatch.fromStoredMap(
        RankedMatch.fromJson(brMatch()).toStoredMap(),
      );
      expect(restored.trackerValue('Tactical: Nitro Gates Used'), isNotNull);
      // Reading twice returns the same decoded list, not a fresh decode.
      expect(identical(restored.trackers, restored.trackers), isTrue);
      // And a copy made for an edit still carries them.
      expect(
        restored.withEdits({'kills': 5}).trackers.length,
        restored.trackers.length,
      );
    });

    test('a corrupt trackers blob is preserved rather than overwritten', () {
      // Decoding degrades to no trackers, but writing the row back must not
      // replace the original blob with "[]" — that would lose it for good.
      final row = RankedMatch.fromJson(brMatch()).toStoredMap();
      row['trackers'] = '{not valid json';
      final restored = RankedMatch.fromStoredMap(row);
      expect(restored.trackers, isEmpty);
      expect(restored.toStoredMap()['trackers'], '{not valid json');
    });

    test('an absent tracker round-trips as null, not zero', () {
      final json = brMatch()..['gameData'] = const [];
      final row = RankedMatch.fromJson(json).toStoredMap();
      expect(row['kills'], isNull);

      final restored = RankedMatch.fromStoredMap(row);
      expect(restored.kills, isNull);
      expect(restored.damage, isNull);
    });

    test('a reported zero round-trips as zero', () {
      final json = brMatch()
        ..['gameData'] = [
          {'key': 'kills', 'value': 0, 'name': 'BR Kills'},
          {'key': 'damage', 'value': 0, 'name': 'BR Damage'},
        ];
      final restored = RankedMatch.fromStoredMap(
        RankedMatch.fromJson(json).toStoredMap(),
      );
      expect(restored.kills, 0);
      expect(restored.damage, 0);
    });
  });

  group('edited fields', () {
    test('encode/decode round-trips and sorts', () {
      expect(encodeEditedFields({'damage', 'kills'}), ',damage,kills,');
      expect(decodeEditedFields(',damage,kills,'), {'damage', 'kills'});
    });

    test('an empty set encodes as null', () {
      expect(encodeEditedFields(const {}), isNull);
      expect(decodeEditedFields(null), isEmpty);
      expect(decodeEditedFields(''), isEmpty);
    });

    test('names that are not editable are dropped on decode', () {
      expect(decodeEditedFields(',kills,uid,'), {'kills'});
    });

    test('a stored row exposes its edited fields', () {
      final row = RankedMatch.fromJson(brMatch()).toStoredMap();
      row['edited_fields'] = ',damage,';
      final m = RankedMatch.fromStoredMap(row);
      expect(m.isEdited, isTrue);
      expect(m.editedFields, {'damage'});
    });

    test('a freshly parsed API match is never marked edited', () {
      expect(RankedMatch.fromJson(brMatch()).isEdited, isFalse);
    });
  });

  group('withEdits', () {
    test('applies a legend/map_key change and marks the field edited', () {
      final m = RankedMatch.fromJson(brMatch());
      final edited = m.withEdits({
        'legend': 'Bangalore',
        'map_key': 'olympus_rotation',
      });

      expect(edited.legend, 'Bangalore');
      expect(edited.mapKey, 'olympus_rotation');
      expect(edited.editedFields, {'legend', 'map_key'});
    });

    // legend/map_key check `is String` and fall back to the current value,
    // rather than casting unconditionally (`as String`), which threw on a
    // null or wrongly-typed value. Unreachable from today's edit form, but
    // withEdits' input is typed no narrower than Map<String, Object?>.
    test(
      'a null legend/map_key change falls back to the current value instead '
      'of throwing',
      () {
        final m = RankedMatch.fromJson(brMatch());
        final edited = m.withEdits({'legend': null, 'map_key': null});

        expect(edited.legend, m.legend);
        expect(edited.mapKey, m.mapKey);
        // Still counts as an edit — the key was present in changes, even
        // though the value that landed is the unchanged original.
        expect(edited.editedFields, {'legend', 'map_key'});
      },
    );

    test(
      'a wrongly-typed legend/map_key change falls back to the current '
      'value instead of throwing',
      () {
        final m = RankedMatch.fromJson(brMatch());
        final edited = m.withEdits({'legend': 42, 'map_key': 7});

        expect(edited.legend, m.legend);
        expect(edited.mapKey, m.mapKey);
      },
    );
  });

  group('excluded', () {
    test('a freshly parsed API match is never excluded', () {
      expect(RankedMatch.fromJson(brMatch()).excluded, isFalse);
    });

    test('withExcluded flips the flag without touching editedFields', () {
      final m = RankedMatch.fromJson(brMatch()).withEdits({'kills': 5});
      final excluded = m.withExcluded(true);

      expect(excluded.excluded, isTrue);
      expect(excluded.editedFields, m.editedFields);
    });

    test('excluded round-trips through toStoredMap/fromStoredMap', () {
      final m = RankedMatch.fromJson(brMatch()).withExcluded(true);
      final restored = RankedMatch.fromStoredMap(m.toStoredMap());
      expect(restored.excluded, isTrue);
    });

    test('effectiveRpChange is zeroed for an excluded match', () {
      final m = RankedMatch.fromJson(brMatch()).withExcluded(true);
      expect(m.rpChange, isNot(0));
      expect(m.effectiveRpChange, 0);
    });
  });

  group('RankedMatch.countsTowardStats', () {
    RankedMatch withRp(int rp) =>
        RankedMatch.fromJson({...brMatch(), 'BRScoreChange': rp});

    test('a plausible ranked match counts', () {
      final m = withRp(44);
      expect(m.isAutoExcluded, isFalse);
      expect(m.countsTowardStats, isTrue);
      expect(m.effectiveRpChange, 44);
    });

    test('an implausible RP swing is excluded automatically', () {
      for (final rp in [-251, -1500, 1000, 4000]) {
        final m = withRp(rp);
        expect(m.isAutoExcluded, isTrue, reason: 'rp=$rp');
        expect(m.countsTowardStats, isFalse, reason: 'rp=$rp');
        expect(m.effectiveRpChange, 0, reason: 'rp=$rp');
      }
    });

    test('the plausible range edges still count', () {
      expect(withRp(-250).countsTowardStats, isTrue);
      expect(withRp(999).countsTowardStats, isTrue);
    });

    test('a hand-excluded match does not count either', () {
      final m = withRp(44).withExcluded(true);
      expect(m.isAutoExcluded, isFalse);
      expect(m.countsTowardStats, isFalse);
      expect(m.effectiveRpChange, 0);
    });

    test('correcting an auto-excluded RP brings the match back', () {
      final fixed = withRp(-1500).withEdits({'rp_change': -60});
      expect(fixed.isAutoExcluded, isFalse);
      expect(fixed.countsTowardStats, isTrue);
      expect(fixed.effectiveRpChange, -60);
    });

    test('a pubs game (0 RP) is not auto-excluded, just not ranked', () {
      final m = withRp(0);
      expect(m.isRanked, isFalse);
      expect(m.isAutoExcluded, isFalse);
    });
  });
}
