import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/map_rotation.dart';
import 'package:apexlytics/utils/formatting/map_alerts_utils.dart';

void main() {
  group('rotationRefreshDelay', () {
    MapMode mode(int secs, {String map = 'Olympus'}) => MapMode(
      map: map,
      remainingSecs: secs,
      durationMins: 60,
      asset: '',
    );

    MapRotation rotation({
      int ranked = 3000,
      int pubs = 3000,
      MapMode? ltm,
      MapMode? rankedBlock,
    }) => MapRotation(
      battleRoyaleCurrent: mode(pubs),
      battleRoyaleNext: mode(3600),
      rankedCurrent: rankedBlock ?? mode(ranked),
      rankedNext: mode(3600),
      ltmCurrent: ltm,
      ltmNext: ltm == null ? null : mode(3600),
    );

    Duration? delay(
      MapRotation r, {
      bool ranked = true,
      bool pubs = false,
      bool mixtape = false,
    }) => rotationRefreshDelay(
      r,
      notifyRanked: ranked,
      notifyPubs: pubs,
      notifyMixtape: mixtape,
      notifyWildcard: false,
    );

    test('waits out the rotation plus the flip buffer', () {
      expect(delay(rotation(ranked: 600)), const Duration(seconds: 615));
    });

    test('never asks again sooner than the proxy cache lifetime', () {
      // A rotation reporting no time left used to be refetched immediately,
      // and again on every answer, until the rate limit pushed back.
      for (final secs in [0, -5, 1, 10]) {
        expect(
          delay(rotation(ranked: secs)),
          kMinRotationRefresh,
          reason: '$secs s left',
        );
      }
    });

    test('is timed to the soonest of the modes being watched', () {
      expect(
        delay(rotation(ranked: 900, pubs: 300), pubs: true),
        const Duration(seconds: 315),
      );
    });

    test('ignores modes that are not being watched', () {
      expect(
        delay(rotation(ranked: 30, pubs: 600), ranked: false, pubs: true),
        const Duration(seconds: 615),
      );
    });

    test('skips a current block upstream left out, instead of reading it as '
        'already ended', () {
      final absent = MapMode.fromJson(const {});

      expect(
        delay(rotation(rankedBlock: absent, pubs: 600), pubs: true),
        const Duration(seconds: 615),
      );
      expect(delay(rotation(rankedBlock: absent)), isNull);
    });

    test('a mode with a map but no time left still counts as ended', () {
      final ended = MapMode.fromJson(const {'map': 'Olympus'});

      expect(delay(rotation(rankedBlock: ended)), kMinRotationRefresh);
    });

    test('a watched mode that is not in the response gives nothing to wait '
        'for', () {
      expect(delay(rotation(), ranked: false, mixtape: true), isNull);
      expect(
        delay(rotation(ltm: mode(1200)), ranked: false, mixtape: true),
        const Duration(seconds: 1215),
      );
    });
  });
}
