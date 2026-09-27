import 'dart:convert';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/models/season_meta.dart';
import 'package:apexlytics/utils/storage/season_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  SeasonMeta season(String id) => SeasonMeta.fromApi(
    id: id,
    startSeconds: 1_780_000_000,
    endSeconds: 1_790_000_000,
  );

  group('SeasonMeta.isSplitId', () {
    test('accepts real split ids', () {
      expect(SeasonMeta.isSplitId('br_ranked_s29_s1'), isTrue);
      expect(SeasonMeta.isSplitId('br_ranked_s30_s2'), isTrue);
    });

    test('rejects placeholders and the unknown bucket', () {
      expect(SeasonMeta.isSplitId('__other__'), isFalse);
      expect(SeasonMeta.isSplitId('__unknown__'), isFalse);
      expect(SeasonMeta.isSplitId(''), isFalse);
    });
  });

  group('season history never stores a placeholder season', () {
    // Its window can overlap the real split's, and a match classified under
    // it would never move to the real one.
    test('upsertSeason ignores a placeholder id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(await upsertSeason(season('__other__'), prefs), isFalse);
      expect(loadAllSeasonsSync(prefs), isEmpty);

      expect(await upsertSeason(season('br_ranked_s29_s1'), prefs), isTrue);
      expect(loadAllSeasonsSync(prefs).keys, ['br_ranked_s29_s1']);
    });

    test('a placeholder stored by an older build is dropped on read', () async {
      SharedPreferences.setMockInitialValues({
        PrefsKeys.seasonHistory: jsonEncode([
          season('__other__').toJson(),
          season('br_ranked_s29_s1').toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(loadAllSeasonsSync(prefs).keys, ['br_ranked_s29_s1']);
    });
  });
}
