import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/formatting/season_utils.dart';
import 'package:apexlytics/utils/formatting/snapshot_types.dart';

/// Split ids either side of a rollover.
const _prevSplit = 'br_ranked_s29_s2';
const _newSplit = 'br_ranked_s30_s1';

/// A player's RP across a split rollover: ended the previous split at 12085,
/// reset to 4420, and climbed to 7240 by the time these fixtures read it.
const _prevSplitFinalRp = 12085;
const _postResetRp = 4420;
const _currentRp = 7240;
const _rpEarnedSinceReset = _currentRp - _postResetRp; // 2820

void main() {
  // Anchored on `now` so the "live week" branch stays exercised forever, rather
  // than on the calendar dates of the original report.
  final now = DateTime.now();
  final splitStart = now.subtract(const Duration(days: 5));
  final liveWeek = WeekRange(
    start: splitStart,
    end: splitStart.add(const Duration(days: 7)),
  );

  StatSnapshot snap(Duration fromSplitStart, int rp, {String? sid}) =>
      StatSnapshot(
        timestamp: splitStart.add(fromSplitStart),
        rp: rp,
        seasonId: sid,
      );

  group('lastResetIndex', () {
    test('flags the snapshot after a split id change', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
        snap(const Duration(hours: 8), _postResetRp, sid: _newSplit),
      ];
      expect(lastResetIndex(snaps), 1);
    });

    test('flags a large drop when split ids are unknown (legacy snapshots)', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp),
        snap(const Duration(hours: 8), _postResetRp),
      ];
      expect(lastResetIndex(snaps, splitStart: splitStart), 1);
    });

    test('ignores a legacy drop observed long after the split opened', () {
      final snaps = [
        snap(const Duration(days: 1), 12000),
        snap(const Duration(days: 20), 10500),
      ];
      expect(lastResetIndex(snaps, splitStart: splitStart), isNull);
    });

    test('a split id change is trusted however late it is observed', () {
      final snaps = [
        snap(const Duration(days: 1), 12000, sid: _prevSplit),
        snap(const Duration(days: 20), 10500, sid: _newSplit),
      ];
      expect(lastResetIndex(snaps, splitStart: splitStart), 1);
    });

    test('falls back to bare magnitude when no split start is known', () {
      // The season-less 24h delta has no window to check a drop against.
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp),
        snap(const Duration(hours: 8), _postResetRp),
      ];
      expect(lastResetIndex(snaps), 1);
    });

    test('does not flag a large drop within a known single split', () {
      final snaps = [
        snap(const Duration(hours: 1), 8000, sid: _newSplit),
        snap(const Duration(days: 3), 6500, sid: _newSplit),
      ];
      expect(lastResetIndex(snaps), isNull);
    });

    test('returns null for a steadily climbing stream', () {
      final snaps = [
        snap(const Duration(hours: 1), 4420, sid: _newSplit),
        snap(const Duration(days: 2), 6170, sid: _newSplit),
        snap(const Duration(days: 4), 7240, sid: _newSplit),
      ];
      expect(lastResetIndex(snaps), isNull);
    });

    test('picks the most recent reset when several are present', () {
      final snaps = [
        snap(const Duration(days: -30), 9000, sid: 'br_ranked_s29_s1'),
        snap(const Duration(days: -20), 2000, sid: _prevSplit),
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
        snap(const Duration(hours: 8), _postResetRp, sid: _newSplit),
      ];
      expect(lastResetIndex(snaps, splitStart: splitStart), 3);
    });
  });

  group('weekDelta across a split reset', () {
    test("never measures week 1 against the previous split's final RP", () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
        snap(const Duration(hours: 8), _postResetRp, sid: _newSplit),
        snap(const Duration(days: 2), 6170, sid: _newSplit),
      ];
      expect(
        weekDelta(
          snaps,
          liveWeek,
          currentRp: _currentRp,
          scopeStart: splitStart,
        ),
        _rpEarnedSinceReset,
      );
    });

    test('works for legacy snapshots that carry no split id', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp),
        snap(const Duration(hours: 8), _postResetRp),
        snap(const Duration(days: 2), 6170),
      ];
      expect(
        weekDelta(
          snaps,
          liveWeek,
          currentRp: _currentRp,
          scopeStart: splitStart,
        ),
        _rpEarnedSinceReset,
      );
    });

    test('rebases when the reset lands after the split start', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp),
        snap(const Duration(minutes: 20), _prevSplitFinalRp),
        snap(const Duration(hours: 8), _postResetRp),
        snap(const Duration(days: 2), 6170),
      ];
      expect(
        weekDelta(
          snaps,
          liveWeek,
          currentRp: _currentRp,
          scopeStart: splitStart,
        ),
        _rpEarnedSinceReset,
      );
    });

    test('still reports a real loss inside a single split', () {
      final snaps = [
        snap(const Duration(hours: 1), 8000, sid: _newSplit),
        snap(const Duration(days: 3), 6500, sid: _newSplit),
      ];
      expect(
        weekDelta(snaps, liveWeek, currentRp: 6500, scopeStart: splitStart),
        -1500,
      );
    });

    test('a reset in an earlier week leaves later weeks alone', () {
      final week2 = WeekRange(
        start: splitStart.add(const Duration(days: 7)),
        end: splitStart.add(const Duration(days: 14)),
      );
      final snaps = [
        StatSnapshot(
          timestamp: splitStart.subtract(const Duration(days: 1)),
          rp: _prevSplitFinalRp,
          seasonId: _prevSplit,
        ),
        StatSnapshot(
          timestamp: week2.start.subtract(const Duration(days: 1)),
          rp: 6170,
          seasonId: _newSplit,
        ),
        StatSnapshot(
          timestamp: week2.start.add(const Duration(days: 1)),
          rp: 6800,
          seasonId: _newSplit,
        ),
      ];
      // Baseline is the last pre-week snapshot (6170), untouched by the reset.
      expect(weekDelta(snaps, week2, scopeStart: splitStart), 630);
    });

    test('returns null when no snapshot is in scope at all', () {
      final snaps = [snap(const Duration(days: -1), _prevSplitFinalRp)];
      expect(
        weekDelta(
          snaps,
          liveWeek,
          currentRp: _currentRp,
          scopeStart: splitStart,
        ),
        isNull,
      );
    });
  });

  group('not enough data to establish a baseline', () {
    test('reports 0 rather than guessing from a single in-week reading', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
        snap(const Duration(days: 4), 6758, sid: _newSplit),
      ];
      expect(
        weekDelta(snaps, liveWeek, currentRp: 6758, scopeStart: splitStart),
        0,
      );
    });

    test('a same-split baseline before the week is enough on its own', () {
      final week2 = WeekRange(
        start: splitStart.add(const Duration(days: 7)),
        end: splitStart.add(const Duration(days: 14)),
      );
      final snaps = [
        StatSnapshot(
          timestamp: week2.start.subtract(const Duration(days: 1)),
          rp: 6000,
          seasonId: _newSplit,
        ),
        StatSnapshot(
          timestamp: week2.start.add(const Duration(days: 1)),
          rp: 6500,
          seasonId: _newSplit,
        ),
      ];
      expect(weekDelta(snaps, week2, scopeStart: splitStart), 500);
    });

    test('a suspect 0 reading is never used as the floor', () {
      final snaps = [
        snap(const Duration(days: -1), 11998),
        snap(const Duration(hours: 8), 0),
        snap(const Duration(days: 4), 6758),
      ];
      expect(
        weekDelta(snaps, liveWeek, currentRp: 6758, scopeStart: splitStart),
        0,
      );
    });

    test('a player who has genuinely never scored still reads as 0', () {
      final snaps = [
        snap(const Duration(days: 1), 0, sid: _newSplit),
        snap(const Duration(days: 2), 0, sid: _newSplit),
      ];
      expect(
        weekDelta(snaps, liveWeek, currentRp: 0, scopeStart: splitStart),
        0,
      );
    });
  });

  group('trustedSnapshots', () {
    test('drops zeros when the stream proves RP was earned', () {
      final snaps = [
        snap(const Duration(days: -1), 11998),
        snap(const Duration(hours: 8), 0),
        snap(const Duration(days: 4), 6758),
      ];
      expect(trustedSnapshots(snaps).map((s) => s.rp), [11998, 6758]);
    });

    test('keeps zeros for a player who has never earned RP', () {
      final snaps = [
        snap(const Duration(days: 1), 0),
        snap(const Duration(days: 2), 0),
      ];
      expect(trustedSnapshots(snaps).length, 2);
    });

    test('leaves an all-positive stream untouched', () {
      final snaps = [
        snap(const Duration(days: 1), 4420),
        snap(const Duration(days: 2), 6170),
      ];
      expect(trustedSnapshots(snaps).map((s) => s.rp), [4420, 6170]);
    });
  });

  group('weekDelta without a reset (unchanged behaviour)', () {
    test('uses the last snapshot before the week as baseline', () {
      final snaps = [
        snap(const Duration(days: -2), 6000, sid: _newSplit),
        snap(const Duration(days: 1), 6500, sid: _newSplit),
      ];
      expect(weekDelta(snaps, liveWeek, currentRp: 7000), 1000);
    });

    test('falls back to the first in-week snapshot with no prior data', () {
      final snaps = [
        snap(const Duration(days: 1), 6500, sid: _newSplit),
        snap(const Duration(days: 2), 6600, sid: _newSplit),
      ];
      expect(weekDelta(snaps, liveWeek, currentRp: 7000), 500);
    });

    test('a past week with no in-week data is a real zero, not null', () {
      final pastWeek = WeekRange(
        start: now.subtract(const Duration(days: 20)),
        end: now.subtract(const Duration(days: 13)),
      );
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(days: 25)),
          rp: 6000,
          seasonId: _newSplit,
        ),
      ];
      expect(weekDelta(snaps, pastWeek), 0);
    });
  });

  group('computeWeekDelta', () {
    // A split window that straddles `now`, so currentWeekIndex lands on week 1.
    final season = SeasonMeta(
      id: _newSplit,
      displayName: 'Season 30 (Split 1)',
      start: splitStart,
      end: splitStart.add(const Duration(days: 42)),
    );

    test('prefers the match-history sum when it is available', () {
      // Snapshots that would produce the wrong answer on their own must not be
      // consulted once history can cover the week.
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
      ];
      expect(
        computeWeekDelta(snaps, season, _currentRp, historyNetRp: 2820),
        2820,
      );
    });

    test('falls back to the reset-aware snapshot path when history is null', () {
      final snaps = [
        snap(const Duration(days: -1), _prevSplitFinalRp, sid: _prevSplit),
        snap(const Duration(hours: 8), _postResetRp, sid: _newSplit),
        snap(const Duration(days: 2), 6170, sid: _newSplit),
      ];
      expect(computeWeekDelta(snaps, season, _currentRp), _rpEarnedSinceReset);
    });

    test('falls back to the 24h delta when there is no season', () {
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 30)),
          rp: 6000,
        ),
      ];
      expect(computeWeekDelta(snaps, null, 6400), 400);
    });
  });

  group('currentWeekRange', () {
    test('returns the week containing now', () {
      final season = SeasonMeta(
        id: _newSplit,
        displayName: 'Season 30 (Split 1)',
        start: splitStart,
        end: splitStart.add(const Duration(days: 42)),
      );
      final week = currentWeekRange(season)!;
      expect(week.start, splitStart);
      expect(week.end, splitStart.add(const Duration(days: 7)));
    });

    test('returns null without a season', () {
      expect(currentWeekRange(null), isNull);
    });
  });

  group('splitContext', () {
    // Matches the live br_ranked_s30_s1 window: 2026-08-04 → 2026-09-15,
    // exactly 42 days, so exactly 6 whole weeks.
    SeasonMeta season(DateTime start, {int days = 42}) => SeasonMeta(
      id: _newSplit,
      displayName: 'Season 30 (Split 1)',
      start: start,
      end: start.add(Duration(days: days)),
    );

    test('reports the 1-based week and total', () {
      final start = DateTime(2026, 8, 4, 10);
      final ctx = splitContext(
        season(start),
        now: start.add(const Duration(days: 8)),
      )!;
      expect(ctx.week, 2);
      expect(ctx.totalWeeks, 6);
      expect(ctx.ended, isFalse);
    });

    test('week 1 on the split opening instant', () {
      final start = DateTime(2026, 8, 4, 10);
      expect(splitContext(season(start), now: start)!.week, 1);
    });

    test('counts a trailing partial week', () {
      final start = DateTime(2026, 8, 4, 10);
      final ctx = splitContext(
        season(start, days: 45),
        now: start.add(const Duration(days: 1)),
      )!;
      expect(ctx.totalWeeks, 7); // 6 whole weeks + a 3-day remainder
    });

    test('reports remaining time until the split ends', () {
      final start = DateTime(2026, 8, 4, 10);
      final ctx = splitContext(
        season(start),
        now: start.add(const Duration(days: 5)),
      )!;
      expect(ctx.remaining.inDays, 37);
    });

    test('clamps to the last week and zero remaining once ended', () {
      final start = DateTime(2026, 8, 4, 10);
      final ctx = splitContext(
        season(start),
        now: start.add(const Duration(days: 50)),
      )!;
      expect(ctx.week, 6);
      expect(ctx.remaining, Duration.zero);
      expect(ctx.ended, isTrue);
    });

    test('returns null without a season', () {
      expect(splitContext(null), isNull);
    });
  });

  group('computeDelta across a reset', () {
    test('reports RP earned since the reset, not the reset itself', () {
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 30)),
          rp: _prevSplitFinalRp,
          seasonId: _prevSplit,
        ),
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 10)),
          rp: _postResetRp,
          seasonId: _newSplit,
        ),
      ];
      expect(computeDelta(snaps, _currentRp), _rpEarnedSinceReset);
    });

    test('leaves an ordinary 24h delta alone', () {
      final snaps = [
        StatSnapshot(
          timestamp: now.subtract(const Duration(hours: 30)),
          rp: 6000,
          seasonId: _newSplit,
        ),
      ];
      expect(computeDelta(snaps, 6400), 400);
    });
  });
}
