import 'package:apexlytics/utils/backup_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  group('when a backup is due', () {
    test('not until 15 days have passed since the last one', () {
      BackupStatus last(int days) => BackupStatus(
        lastBackup: daysAgo(days),
        newGames: 5,
        oldestGame: daysAgo(200),
      );

      expect(last(14).isDue(now), isFalse);
      expect(last(15).isDue(now), isTrue);
      expect(last(40).isDue(now), isTrue);
    });

    test('not when no games were recorded since', () {
      final status = BackupStatus(
        lastBackup: daysAgo(90),
        newGames: 0,
        oldestGame: daysAgo(200),
      );

      expect(status.isDue(now), isFalse);
    });

    test('with no backup yet, measures from the oldest recorded game', () {
      BackupStatus first(int days) => BackupStatus(
        lastBackup: null,
        newGames: 30,
        oldestGame: daysAgo(days),
      );

      expect(first(10).isDue(now), isFalse);
      expect(first(15).isDue(now), isTrue);
    });

    test('with nothing recorded and no backup, never', () {
      const status = BackupStatus(
        lastBackup: null,
        newGames: 0,
        oldestGame: null,
      );

      expect(status.gap(now), isNull);
      expect(status.isDue(now), isFalse);
    });

    test('a backup made today is not due, however many games came after', () {
      final status = BackupStatus(
        lastBackup: now,
        newGames: 12,
        oldestGame: daysAgo(100),
      );

      expect(status.isDue(now), isFalse);
    });
  });

  group('backupAgeLabel', () {
    test('says today and yesterday by the calendar day', () {
      expect(backupAgeLabel(DateTime(2026, 10, 20, 1), now), 'today');
      expect(backupAgeLabel(DateTime(2026, 10, 19, 23), now), 'yesterday');
    });

    test('counts days, then months', () {
      expect(backupAgeLabel(daysAgo(12), now), '12 days ago');
      expect(backupAgeLabel(daysAgo(59), now), '59 days ago');
      expect(backupAgeLabel(daysAgo(60), now), '2 months ago');
      expect(backupAgeLabel(daysAgo(400), now), '13 months ago');
    });
  });
}
