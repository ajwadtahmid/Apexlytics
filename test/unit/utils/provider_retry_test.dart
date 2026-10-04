import 'package:apexlytics/utils/error_messages.dart';
import 'package:apexlytics/utils/provider_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('transientProviderRetry', () {
    test('never retries a definite client-side answer', () {
      for (final status in [400, 401, 403, 404, 410, 429]) {
        expect(
          transientProviderRetry(0, AppException('x', status: status)),
          isNull,
          reason: 'status $status',
        );
      }
    });

    test('retries a 5xx or a transport failure, with growing pauses', () {
      final first = transientProviderRetry(
        0,
        const AppException('x', status: 503),
      );
      final second = transientProviderRetry(1, const AppException('x'));
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second! > first!, isTrue);
    });

    test('gives up after kProviderMaxRetries', () {
      expect(
        transientProviderRetry(kProviderMaxRetries, const AppException('x')),
        isNull,
      );
    });

    test('never retries an Error (a bug, not a transient failure)', () {
      expect(transientProviderRetry(0, StateError('bug')), isNull);
      expect(transientProviderRetry(0, TypeError()), isNull);
    });

    test('retries any other exception', () {
      expect(transientProviderRetry(0, Exception('db locked')), isNotNull);
    });
  });
}
