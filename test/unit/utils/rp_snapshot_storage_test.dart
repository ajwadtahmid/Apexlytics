import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/utils/storage/rp_snapshot_storage.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';

import '../../helpers.dart';

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
