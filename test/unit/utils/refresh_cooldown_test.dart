import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/refresh_cooldown.dart';

void main() {
  group('RefreshCooldown', () {
    test('first fire for a key succeeds', () {
      final cooldown = RefreshCooldown();
      expect(cooldown.tryFire('a'), isTrue);
    });

    test('a second fire for the same key within the window is blocked', () {
      final cooldown = RefreshCooldown(duration: const Duration(seconds: 10));
      expect(cooldown.tryFire('a'), isTrue);
      expect(cooldown.tryFire('a'), isFalse);
    });

    test('a blocked fire does not reset the cooldown window', () async {
      final cooldown = RefreshCooldown(
        duration: const Duration(milliseconds: 30),
      );
      expect(cooldown.tryFire('a'), isTrue);
      expect(cooldown.tryFire('a'), isFalse);
      await Future.delayed(const Duration(milliseconds: 40));
      expect(cooldown.tryFire('a'), isTrue);
    });

    test('different keys are independent', () {
      final cooldown = RefreshCooldown(duration: const Duration(seconds: 10));
      expect(cooldown.tryFire('a'), isTrue);
      expect(cooldown.tryFire('b'), isTrue);
    });

    test('fires again once the cooldown window elapses', () async {
      final cooldown = RefreshCooldown(
        duration: const Duration(milliseconds: 20),
      );
      expect(cooldown.tryFire('a'), isTrue);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(cooldown.tryFire('a'), isTrue);
    });

    test('purging expired keys leaves an active key still cooling down', () {
      final cooldown = RefreshCooldown(duration: const Duration(seconds: 10));
      expect(cooldown.tryFire('a'), isTrue);
      // Firing 'b' sweeps expired entries; 'a' is still inside its window and
      // survives the sweep.
      expect(cooldown.tryFire('b'), isTrue);
      expect(cooldown.tryFire('a'), isFalse);
    });

    test('a key that expired during another key\'s window is swept', () async {
      final cooldown = RefreshCooldown(
        duration: const Duration(milliseconds: 20),
      );
      expect(cooldown.tryFire('a'), isTrue);
      await Future.delayed(const Duration(milliseconds: 30));
      // 'b' sweeps the now-expired 'a', which then fires as a first-time key.
      expect(cooldown.tryFire('b'), isTrue);
      expect(cooldown.tryFire('a'), isTrue);
    });
  });
}
