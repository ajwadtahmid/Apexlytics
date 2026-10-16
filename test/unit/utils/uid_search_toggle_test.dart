import 'package:apexlytics/widgets/uid_search_toggle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikeUid', () {
    test('needs at least 10 digits', () {
      expect(looksLikeUid('123456789'), isFalse);
      expect(looksLikeUid('1234567890'), isTrue);
    });

    test('rejects names, even long ones', () {
      expect(looksLikeUid('Player1234567890'), isFalse);
      expect(looksLikeUid(''), isFalse);
    });
  });
}
