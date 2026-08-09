import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/utils/storage/rp_snapshot_storage.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';
import 'package:apexlytics/models/season_meta.dart';

import '../../helpers.dart';

/// A ranked split window; only the id matters for snapshot stamping.
SeasonMeta _split(String id) =>
    SeasonMeta.fromApi(id: id, startSeconds: 1000, endSeconds: 999999);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loadSnapshotsSync', () {
    test('returns empty list when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(loadSnapshotsSync(prefs), isEmpty);
    });

    test('returns empty list on corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({'stat_snapshots': 'bad'});
      final prefs = await SharedPreferences.getInstance();
      expect(loadSnapshotsSync(prefs), isEmpty);
    });

    test('loads snapshots keyed by UID', () async {
      final snapshot = [
        {'ts': DateTime.now().millisecondsSinceEpoch, 'rp': 1500},
      ];
      SharedPreferences.setMockInitialValues({
        'stat_snapshots_uid123': jsonEncode(snapshot),
      });
      final prefs = await SharedPreferences.getInstance();
      final result = loadSnapshotsSync(prefs, uid: 'uid123');
      expect(result.length, 1);
      expect(result.first.rp, 1500);
    });

    test('falls back to generic key when uid is null', () async {
      final snapshot = [
        {'ts': DateTime.now().millisecondsSinceEpoch, 'rp': 800},
      ];
      SharedPreferences.setMockInitialValues({
        'stat_snapshots': jsonEncode(snapshot),
      });
      final prefs = await SharedPreferences.getInstance();
      final result = loadSnapshotsSync(prefs);
      expect(result.first.rp, 800);
    });
  });

  group('appendSnapshot', () {
    test('appends a new snapshot', () async {
      final prefs = await SharedPreferences.getInstance();
      final stats = buildStats(rankScore: 2400);
      await appendSnapshot(stats, prefs);
      final snaps = loadSnapshotsSync(prefs);
      expect(snaps.length, 1);
      expect(snaps.first.rp, 2400);
    });

    test('deduplicates when RP is unchanged', () async {
      final prefs = await SharedPreferences.getInstance();
      final stats = buildStats(rankScore: 2400);
      await appendSnapshot(stats, prefs);
      await appendSnapshot(stats, prefs);
      expect(loadSnapshotsSync(prefs).length, 1);
    });

    test('does NOT deduplicate when deduplicateRp is false', () async {
      final prefs = await SharedPreferences.getInstance();
      final stats = buildStats(rankScore: 2400);
      await appendSnapshot(stats, prefs, deduplicateRp: false);
      await appendSnapshot(stats, prefs, deduplicateRp: false);
      expect(loadSnapshotsSync(prefs).length, 2);
    });

    test('appends when RP changes', () async {
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(buildStats(rankScore: 2400), prefs);
      await appendSnapshot(buildStats(rankScore: 2500), prefs);
      final snaps = loadSnapshotsSync(prefs);
      expect(snaps.length, 2);
      expect(snaps.last.rp, 2500);
    });

    test('stamps the current split id onto the snapshot', () async {
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s30_s1')),
        prefs,
      );
      expect(loadSnapshotsSync(prefs).single.seasonId, 'br_ranked_s30_s1');
    });

    test('leaves the split id null when the season is unknown', () async {
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(buildStats(rankScore: 4420), prefs);
      expect(loadSnapshotsSync(prefs).single.seasonId, isNull);
    });

    test('appends across a split change even when RP is unchanged', () async {
      // This entry is what marks where the reset fell in the stream, so dedup
      // must not swallow it just because the RP number happens to repeat.
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s29_s2')),
        prefs,
      );
      await appendSnapshot(
        buildStats(rankScore: 4420, rankedSeason: _split('br_ranked_s30_s1')),
        prefs,
      );
      final snaps = loadSnapshotsSync(prefs);
      expect(snaps.length, 2);
      expect(snaps.last.seasonId, 'br_ranked_s30_s1');
    });

    test('still deduplicates within the same split', () async {
      final prefs = await SharedPreferences.getInstance();
      final stats = buildStats(
        rankScore: 4420,
        rankedSeason: _split('br_ranked_s30_s1'),
      );
      await appendSnapshot(stats, prefs);
      await appendSnapshot(stats, prefs);
      expect(loadSnapshotsSync(prefs).length, 1);
    });

    test('rejects a 0 reading once RP has been earned', () async {
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(buildStats(rankScore: 11998), prefs);
      await appendSnapshot(buildStats(rankScore: 0), prefs);
      final snaps = loadSnapshotsSync(prefs);
      expect(snaps.length, 1);
      expect(snaps.single.rp, 11998);
    });

    test('records 0 for a player who has never earned RP', () async {
      final prefs = await SharedPreferences.getInstance();
      await appendSnapshot(buildStats(rankScore: 0), prefs);
      expect(loadSnapshotsSync(prefs).single.rp, 0);
    });

    test('legacy entries without a split id still load', () async {
      SharedPreferences.setMockInitialValues({
        'stat_snapshots': jsonEncode([
          {'ts': DateTime.now().millisecondsSinceEpoch, 'rp': 12085},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final snap = loadSnapshotsSync(prefs).single;
      expect(snap.rp, 12085);
      expect(snap.seasonId, isNull);
    });

    test('stores snapshot under uid-specific key', () async {
      final prefs = await SharedPreferences.getInstance();
      final stats = buildStats(rankScore: 3000, uid: 'abc');
      await appendSnapshot(stats, prefs, uid: 'abc');
      final withUid = loadSnapshotsSync(prefs, uid: 'abc');
      final withoutUid = loadSnapshotsSync(prefs);
      expect(withUid.length, 1);
      expect(withoutUid, isEmpty);
    });
  });

  group('computeDelta', () {
    test('returns null for empty snapshot list', () {
      expect(computeDelta([], 1000), isNull);
    });

    test('returns current minus oldest when all snapshots are within 24h', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 2)), rp: 1000),
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 1)), rp: 1200),
      ];
      expect(computeDelta(snaps, 1300), 300);
    });

    test('uses most-recent snapshot older than 24h as baseline', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 48)), rp: 800),
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 25)), rp: 1000),
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 1)), rp: 1300),
      ];
      // Baseline = most recent before 24h = 1000
      expect(computeDelta(snaps, 1400), 400);
    });

    test('handles negative delta (demotion)', () {
      final now = DateTime.now();
      final snaps = [
        StatSnapshot(timestamp: now.subtract(const Duration(hours: 25)), rp: 2000),
      ];
      expect(computeDelta(snaps, 1800), -200);
    });
  });
}
