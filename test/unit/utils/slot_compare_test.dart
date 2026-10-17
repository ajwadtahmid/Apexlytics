import 'package:apexlytics/utils/ranked/slot_compare.dart';
import 'package:flutter_test/flutter_test.dart';

Slot _s(int slot, int games, int netRp) =>
    (slot: slot, games: games, netRp: netRp);

String _label(int h) => 'h$h';

void main() {
  group('hourAxis', () {
    test('runs from the first hour played to the last', () {
      expect(hourAxis([9, 10, 21]), [for (var h = 9; h <= 21; h++) h]);
    });

    test('wraps past midnight rather than spanning the whole day', () {
      expect(hourAxis([22, 23, 0, 1]), [22, 23, 0, 1]);
      expect(hourAxis([23, 2]), [23, 0, 1, 2]);
    });

    test('is one hour for one hour, and the whole day when none is idle', () {
      expect(hourAxis([14, 14]), [14]);
      expect(hourAxis([for (var h = 0; h < 24; h++) h]), [
        for (var h = 0; h < 24; h++) h,
      ]);
    });

    test('is the whole day when nothing was played', () {
      expect(hourAxis(const []), hasLength(24));
    });
  });

  group('bestSlot', () {
    test('picks the highest RP per game, not the most RP', () {
      final slots = [_s(9, 10, 50), _s(21, 4, 40)]; // +5 a game vs +10
      expect(bestSlot(slots)!.slot, 21);
    });

    test('the weakest is the lowest RP per game', () {
      final slots = [_s(9, 10, 50), _s(21, 4, -8), _s(23, 5, 0)];
      expect(bestSlot(slots, best: false)!.slot, 21);
    });

    test('ignores slots with too few games to read anything into', () {
      final slots = [_s(3, 2, 100), _s(9, 5, 10)];
      expect(bestSlot(slots)!.slot, 9);
      expect(bestSlot([_s(3, 2, 100)]), isNull);
    });

    test('a tie goes to the slot played more, then the earlier', () {
      expect(bestSlot([_s(9, 4, 20), _s(10, 8, 40)])!.slot, 10);
      expect(bestSlot([_s(11, 4, 20), _s(10, 4, 20)])!.slot, 10);
    });
  });

  group('slotVerdict', () {
    String? verdict(List<Slot> a, List<Slot> b, {bool best = true}) =>
        slotVerdict(what: 'hour', label: _label, a: a, b: b, best: best);

    test('says where the best moved to', () {
      expect(
        verdict([_s(9, 5, 50)], [_s(23, 5, 50)]),
        'Best hour moved from h9 to h23',
      );
    });

    test('says when it stayed', () {
      expect(verdict([_s(9, 5, 50)], [_s(9, 6, 10)]), 'Best hour stayed h9');
    });

    test('the weakest line is worded as weakest', () {
      expect(
        verdict([_s(9, 5, -50)], [_s(4, 5, -20)], best: false),
        'Weakest hour moved from h9 to h4',
      );
    });

    test('is null when either side has no slot with enough games', () {
      expect(verdict([_s(9, 5, 50)], [_s(9, 1, 50)]), isNull);
      expect(verdict(const [], [_s(9, 5, 50)]), isNull);
    });
  });
}
