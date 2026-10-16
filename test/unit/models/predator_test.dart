import 'package:apexlytics/models/predator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses each platform\'s cutoff', () {
    final r = PredatorResponse.fromJson({
      'RP': {
        'PC': {'val': 18000, 'totalMastersAndPreds': 900},
      },
    });
    expect(r.forPlatform('PC')?.minRp, 18000);
    expect(r.forPlatform('PC')?.totalMastersAndPreds, 900);
  });

  test('an RP block that is not an object reads as no data, not an error', () {
    // A PHP-backed API sends an empty object as `[]`.
    final r = PredatorResponse.fromJson({'RP': []});
    expect(r.rp, isEmpty);
    expect(r.forPlatform('PC'), isNull);
  });

  test('a platform entry that is not an object is skipped', () {
    final r = PredatorResponse.fromJson({
      'RP': {
        'PC': [],
        'PS4': {'val': 1},
      },
    });
    expect(r.rp.keys, ['PS4']);
  });
}
