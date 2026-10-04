import 'dart:io';

import 'package:apexlytics/utils/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('friendlyError for file system failures', () {
    FileSystemException failure(int? code) => FileSystemException(
      'Cannot create file',
      '/home/someone/Documents/apexlytics_backup.json.gz',
      code == null ? null : OSError('os message', code),
    );

    test('a permission error says to pick another location', () {
      for (final code in [1, 13, 5, 30, 19]) {
        final message = friendlyError(failure(code));
        expect(message, contains('permission'), reason: 'code $code');
        expect(message, contains('different'), reason: 'code $code');
      }
    });

    test('a full disk says so', () {
      for (final code in [28, 112]) {
        expect(
          friendlyError(failure(code)),
          contains('storage space'),
          reason: 'code $code',
        );
      }
    });

    test('any other file error still gets a specific, actionable message', () {
      expect(friendlyError(failure(2)), contains('Try a different location'));
      expect(friendlyError(failure(null)), contains('Try a different location'));
    });

    test('never includes the path, which can carry the user\'s name', () {
      for (final code in [1, 28, 2, null]) {
        final message = friendlyError(failure(code));
        expect(message, isNot(contains('someone')));
        expect(message, isNot(contains('apexlytics_backup')));
        expect(message, isNot(contains('os message')));
      }
    });
  });

  test('a MalformedResponseException keeps its own message', () {
    expect(
      friendlyError(const MalformedResponseException('Unexpected response.')),
      'Unexpected response.',
    );
  });
}
