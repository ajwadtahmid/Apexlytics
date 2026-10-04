import 'dart:convert';

import 'package:apexlytics/utils/crash_report_scrubber.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _uid = '1006838015507';
const _name = 'SomePlayerName';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('scrubForCrashReport', () {
    test('drops the source excerpt a FormatException carries', () {
      // The shape that reaches the logger when the stored profile list is
      // corrupt: its excerpt lines quote names and UIDs.
      late FormatException error;
      try {
        jsonDecode('[{"name":"$_name","uid":"$_uid",,}]');
      } on FormatException catch (e) {
        error = e;
      }
      expect(error.toString(), contains(_name)); // the risk is real...

      final scrubbed = scrubForCrashReport(error.toString());
      expect(scrubbed, isNot(contains(_name))); // ...and removed
      expect(scrubbed, isNot(contains(_uid)));
      expect(scrubbed, startsWith('FormatException'));
    });

    test("drops a sqflite error's SQL arguments", () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE t (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
      await db.insert('t', {'id': '${_uid}_100', 'name': _name});

      late Object error;
      try {
        // Duplicate primary key — fails with the arguments quoted.
        await db.rawInsert('INSERT INTO t (id, name) VALUES (?, ?)', [
          '${_uid}_100',
          _name,
        ]);
      } catch (e) {
        error = e;
      }
      expect(error.toString(), contains(_name));

      final scrubbed = scrubForCrashReport(error.toString());
      expect(scrubbed, isNot(contains(_name)));
      expect(scrubbed, isNot(contains(_uid)));
      expect(scrubbed, contains('UNIQUE constraint failed'));
    });

    test('masks anything UID-shaped', () {
      expect(
        scrubForCrashReport('rank_goal_$_uid missing'),
        'rank_goal_<uid> missing',
      );
      // Short numbers (counts, statuses) are left alone.
      expect(scrubForCrashReport('HTTP 404 after 3 retries'), 'HTTP 404 after 3 retries');
    });

    test('caps the length', () {
      final scrubbed = scrubForCrashReport('x' * 1000);
      expect(scrubbed.length, lessThanOrEqualTo(301));
    });
  });

  group('Sentry hooks', () {
    test('scrubSentryEvent scrubs exceptions, message and breadcrumbs', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FormatException',
            value: 'Unexpected character\n{"name":"$_name"}',
          ),
        ],
        message: SentryMessage('lookup for $_uid failed'),
        breadcrumbs: [
          Breadcrumb(
            message: 'Stats sync failed',
            data: {'error': "DatabaseException(x) sql 'INSERT' args [$_name]"},
          ),
        ],
      );

      final scrubbed = scrubSentryEvent(event, Hint());

      expect(scrubbed.exceptions!.single.value, 'Unexpected character');
      expect(scrubbed.message!.formatted, 'lookup for <uid> failed');
      expect(scrubbed.breadcrumbs!.single.data!['error'], 'DatabaseException(x)');
    });

    test('scrubSentryEvent drops the event user', () {
      final event = SentryEvent(user: SentryUser(id: 'per-install-id'));

      expect(scrubSentryEvent(event, Hint()).user, isNull);
    });

    test('scrubSentryBreadcrumb scrubs the message and string data only', () {
      final crumb = scrubSentryBreadcrumb(
        Breadcrumb(
          message: 'failed for $_uid',
          data: {'error': 'x\n$_name', 'count': 3},
        ),
        Hint(),
      )!;

      expect(crumb.message, 'failed for <uid>');
      expect(crumb.data, {'error': 'x', 'count': 3});
    });
  });
}
