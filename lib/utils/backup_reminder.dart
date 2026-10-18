/// How long the recorded history can go without a backup before Settings says
/// so (when games were recorded in that time).
const kBackupReminderAfter = Duration(days: 15);

/// Where the match history stands against the last backup.
class BackupStatus {
  /// When history was last exported, or null if it never was.
  final DateTime? lastBackup;

  /// Games recorded since [lastBackup], or every recorded game if never.
  final int newGames;

  /// When the oldest recorded game started; the clock to measure from while
  /// there is no backup. Null with no games.
  final DateTime? oldestGame;

  const BackupStatus({
    required this.lastBackup,
    required this.newGames,
    required this.oldestGame,
  });

  /// How long the unsaved games have gone without a backup, or null with
  /// nothing to measure from.
  Duration? gap(DateTime now) {
    final from = lastBackup ?? oldestGame;
    return from == null ? null : now.difference(from);
  }

  /// Whether Settings should nudge: [kBackupReminderAfter] has passed and
  /// there are games a backup does not hold.
  bool isDue(DateTime now) {
    final gap = this.gap(now);
    return gap != null && gap >= kBackupReminderAfter && newGames > 0;
  }
}

/// "Last backup: 12 days ago" style wording for [at] as seen from [now].
String backupAgeLabel(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 60) return '$days days ago';
  final months = days ~/ 30;
  return '$months months ago';
}
