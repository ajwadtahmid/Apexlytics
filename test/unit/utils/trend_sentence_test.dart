import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/widgets/trend_lines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TrendSentence say(
    double recent,
    double overall, {
    int decimals = 1,
    bool signed = false,
    String label = 'Avg',
  }) => trendSentence(
    label,
    TrendChange(recent: recent, overall: overall),
    decimals: decimals,
    signed: signed,
  );

  group('the cases that used to print figures that did not add up', () {
    test('kills: 2.2 and 1.9 are 0.3 apart, not 0.4', () {
      // 2.24 and 1.86 are 0.38 apart, which rounds to 0.4.
      expect(
        say(2.24, 1.86, label: 'Avg Kills').text,
        'Avg Kills 2.2 lately, 0.3 above your 1.9 average',
      );
    });

    test('kills: 2.3 and 1.8 are 0.5 apart, not 0.4', () {
      expect(
        say(2.26, 1.84, label: 'Avg Kills').text,
        'Avg Kills 2.3 lately, 0.5 above your 1.8 average',
      );
    });

    test('damage: 942 and 879 are 63 apart, not 62', () {
      expect(
        say(941.6, 879.4, decimals: 0, label: 'Avg Damage').text,
        'Avg Damage 942 lately, 63 above your 879 average',
      );
    });

    test('RP: +57.0 and +25.4 are 31.6 apart, not 31.7', () {
      expect(
        say(57.04, 25.36, signed: true, label: 'Avg RP').text,
        'Avg RP +57.0 lately, 31.6 above your +25.4 average',
      );
    });

    test('the example from the sheet reads as it should', () {
      // Mad Maggie: the last 18 games at +57.0, all 70 at +25.4.
      expect(
        say(57.0, 25.4, signed: true, label: 'Avg RP').text,
        'Avg RP +57.0 lately, 31.6 above your +25.4 average',
      );
    });
  });

  group('for any figures', () {
    // "<label> <recent> lately, <distance> above|below your <overall> average".
    final pattern = RegExp(
      r'^\S+ (\S+) lately, (\S+) (above|below) your (\S+) average$',
    );

    double number(String text) => double.parse(text.replaceAll(',', ''));

    void checkAdds(TrendSentence sentence, {required String context}) {
      final m = pattern.firstMatch(sentence.text);
      expect(m, isNotNull, reason: '$context: ${sentence.text}');
      final recent = number(m!.group(1)!);
      final distance = number(m.group(2)!);
      final overall = number(m.group(4)!);
      final above = m.group(3) == 'above';
      expect(
        above ? recent - overall : overall - recent,
        closeTo(distance, 1e-9),
        reason: '$context: ${sentence.text}',
      );
      // And never the wrong way round.
      expect(distance, greaterThan(0), reason: '$context: ${sentence.text}');
      expect(sentence.direction, above ? 1 : -1);
    }

    test('one decimal place: what is printed adds up', () {
      var checked = 0;
      for (var r = 0.0; r < 6.0; r += 0.0137) {
        for (var o = 0.0; o < 6.0; o += 0.0191) {
          final s = say(r, o);
          if (s.direction == 0) continue;
          checkAdds(s, context: '$r vs $o');
          checked++;
        }
      }
      expect(checked, greaterThan(50000));
    });

    test('signed RP, including losses: what is printed adds up', () {
      var checked = 0;
      for (var r = -80.0; r < 120.0; r += 0.731) {
        for (var o = -60.0; o < 100.0; o += 0.937) {
          final s = say(r, o, signed: true);
          if (s.direction == 0) continue;
          checkAdds(s, context: '$r vs $o');
          checked++;
        }
      }
      expect(checked, greaterThan(40000));
    });

    test('whole numbers (damage), with thousands separators', () {
      var checked = 0;
      for (var r = 0.0; r < 3200.0; r += 7.31) {
        for (var o = 0.0; o < 3200.0; o += 11.9) {
          final s = say(r, o, decimals: 0);
          if (s.direction == 0) continue;
          checkAdds(s, context: '$r vs $o');
          checked++;
        }
      }
      expect(checked, greaterThan(40000));
    });
  });

  group('in line with the average', () {
    test('when the figures shown are the same', () {
      expect(say(2.21, 2.24).direction, 0);
      expect(say(2.249, 2.201).direction, 0); // both show as 2.2
      expect(say(2.21, 2.24).text, 'Avg in line with your average');
    });

    test('when they are within half the last place, however they round', () {
      // 2.26 and 2.24 show as 2.3 and 2.2, but are not really apart.
      expect(say(2.26, 2.24).direction, 0);
      expect(say(880.2, 879.8, decimals: 0).direction, 0);
    });

    test('not when a whole last place apart', () {
      expect(say(2.3, 2.2).direction, 1);
      expect(say(2.2, 2.3).direction, -1);
    });
  });

  test('says below, with the distance as a positive number', () {
    expect(
      say(10.0, 25.4, signed: true, label: 'Avg RP').text,
      'Avg RP +10.0 lately, 15.4 below your +25.4 average',
    );
    expect(
      say(-12.0, 5.0, signed: true, label: 'Avg RP').text,
      'Avg RP -12.0 lately, 17.0 below your +5.0 average',
    );
  });
}
