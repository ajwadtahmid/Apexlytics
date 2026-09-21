import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/season_meta.dart';

void main() {
  group('SeasonMeta.fromApi displayName', () {
    test('formats a well-formed split id', () {
      final season = SeasonMeta.fromApi(
        id: 'br_ranked_s30_s2',
        startSeconds: 0,
        endSeconds: 1,
      );
      expect(season.displayName, 'Season 30 (Split 2)');
    });

    test(
      'falls back to "Other" for a non-split id, instead of leaking the '
      'raw upstream string (e.g. the API\'s "__other__" placeholder season)',
      () {
        final season = SeasonMeta.fromApi(
          id: '__other__',
          startSeconds: 0,
          endSeconds: 1,
        );
        expect(season.displayName, 'Other');
      },
    );

    test('fromJson applies the same fallback on reload', () {
      final season = SeasonMeta.fromJson({
        'id': '__other__',
        'start': 0,
        'end': 1000,
      });
      expect(season!.displayName, 'Other');
    });
  });
}
