import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/models/ranked_match.dart';
import 'package:apexlytics/providers/ranked_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/match_edit_sheet.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart' show kUnknownSplitId;
import 'package:apexlytics/utils/storage/ranked_history_store.dart';

/// In-memory stand-in for [RankedHistoryStore]'s edit surface. The store's
/// own SQL behaviour (upsert conflict rules, `editMatch`'s range checks,
/// `getBySeason`'s NULL/Unknown fold, ...) is already thoroughly covered by
/// `ranked_history_store_test.dart` — this widget test only needs to verify
/// [MatchEditSheet] calls the store correctly and reacts to what it returns,
/// so a fake avoids combining sqflite_common_ffi with testWidgets' fake-async
/// pumping (which does not settle reliably for real FFI I/O).
class _FakeStore extends RankedHistoryStore {
  final Map<String, RankedMatch> rows;

  _FakeStore(List<RankedMatch> seed)
    : rows = {for (final m in seed) m.dedupKey: m};

  @override
  Future<List<RankedMatch>> getAll(String uid) async =>
      rows.values.where((m) => m.uid == uid).toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));

  @override
  Future<List<RankedMatch>> getBySeason(String uid, String seasonId) =>
      getAll(uid);

  @override
  Future<bool> editMatch(String id, Map<String, Object?> values) async {
    final existing = rows[id];
    if (existing == null) return false;
    rows[id] = existing.withEdits(values);
    return true;
  }

  @override
  Future<void> clearEdits(String id, {String? field}) async {
    final existing = rows[id];
    if (existing == null) return;
    rows[id] = existing.withEditsCleared(field);
  }
}

/// Covers the only path a user directly writes to the match store (a real
/// bug in this file a single test would have caught).
void main() {
  const uid = '1';

  RankedMatch match({int rp = 20, Set<String> editedFields = const {}}) {
    final base = RankedMatch.fromJson({
      'uid': uid,
      'name': 'Tester',
      'legendPlayed': 'Axle',
      'gameMode': 'BATTLE_ROYALE',
      'gameLengthSecs': 600,
      'gameStartTimestamp': 0,
      'gameEndTimestamp': 600,
      'gameData': [
        {'key': 'kills', 'value': 3, 'name': 'BR Kills'},
        {'key': 'damage', 'value': 1000, 'name': 'BR Damage'},
      ],
      'BRScoreChange': rp,
      'BRScore': 1000 + rp,
      'map': 'olympus_rotation',
      'isPartyFull': false,
    });
    return editedFields.isEmpty
        ? base
        : RankedMatch.fromStoredMap({
            ...base.toStoredMap(),
            'edited_fields': encodeEditedFields(editedFields),
          });
  }

  Future<SharedPreferences> emptyPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  /// Pumps a screen with a button that opens [MatchEditSheet] for [match] via
  /// the real [showMatchEditSheet] entry point (so Navigator.pop semantics
  /// match production), capturing whatever it resolves to in [onResult].
  Widget app({
    required RankedMatch match,
    required _FakeStore store,
    required SharedPreferences prefs,
    required ValueChanged<RankedMatch?> onResult,
  }) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rankedHistoryStoreProvider.overrideWithValue(store),
        rankedSyncProvider(
          uid,
        ).overrideWith((ref) async => RankedSyncOutcome.synced),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final r = await showMatchEditSheet(context, match);
                onResult(r);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('saving a valid RP correction persists it and closes', (
    tester,
  ) async {
    final m = match();
    final store = _FakeStore([m]);
    RankedMatch? result;

    await tester.pumpWidget(
      app(
        match: m,
        store: store,
        prefs: await emptyPrefs(),
        onResult: (r) => result = r,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '55');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Sheet closed and returned the edited copy.
    expect(find.text('Correct this match'), findsNothing);
    expect(result, isNotNull);
    expect(result!.rpChange, 55);
    expect(result!.editedFields, contains('rp_change'));

    // And the correction actually persisted to the store, not just the
    // in-memory copy handed back to the caller.
    final stored = store.rows[m.dedupKey]!;
    expect(stored.rpChange, 55);
    expect(stored.editedFields, contains('rp_change'));
  });

  testWidgets(
    'setting RP change to 0 warns before saving, and Cancel keeps the sheet open',
    (tester) async {
      final m = match();
      final store = _FakeStore([m]);
      RankedMatch? result;

      await tester.pumpWidget(
        app(
          match: m,
          store: store,
          prefs: await emptyPrefs(),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The warning dialog is up, sheet still open, nothing saved yet.
      expect(find.text('RP change is 0'), findsOneWidget);
      expect(find.text('Correct this match'), findsOneWidget);
      expect(result, isNull);

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      // Dialog dismissed, sheet still open, store untouched.
      expect(find.text('RP change is 0'), findsNothing);
      expect(find.text('Correct this match'), findsOneWidget);
      expect(result, isNull);
      expect(store.rows[m.dedupKey]!.rpChange, m.rpChange);
    },
  );

  testWidgets(
    '"Save anyway" on the 0-RP warning persists the correction',
    (tester) async {
      final m = match();
      final store = _FakeStore([m]);
      RankedMatch? result;

      await tester.pumpWidget(
        app(
          match: m,
          store: store,
          prefs: await emptyPrefs(),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      expect(find.text('Correct this match'), findsNothing);
      expect(result, isNotNull);
      expect(result!.rpChange, 0);
      expect(store.rows[m.dedupKey]!.rpChange, 0);
    },
  );

  testWidgets('an out-of-range RP change shows an error and does not save', (
    tester,
  ) async {
    final m = match();
    final store = _FakeStore([m]);
    RankedMatch? result;

    await tester.pumpWidget(
      app(
        match: m,
        store: store,
        prefs: await emptyPrefs(),
        onResult: (r) => result = r,
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // kMaxEditableRpChange is kRankedOutlierThreshold - 1 (999) - 5000 is
    // well past it.
    await tester.enterText(find.byType(TextField).last, '5000');
    await tester.pump();

    expect(find.text('RP change seems too high'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Still open, nothing saved.
    expect(find.text('Correct this match'), findsOneWidget);
    expect(result, isNull);
    expect(store.rows[m.dedupKey]!.rpChange, m.rpChange);
  });

  testWidgets(
    'a match no longer in the store reports the failure instead of a '
    'false success',
    (tester) async {
      // Deliberately not seeded - editMatch will find no row for this id.
      final store = _FakeStore(const []);
      final m = match();
      RankedMatch? result;

      await tester.pumpWidget(
        app(
          match: m,
          store: store,
          prefs: await emptyPrefs(),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '55');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text('That match is no longer in your history.'),
        findsOneWidget,
      );
      expect(result, isNull);
    },
  );

  testWidgets(
    '"Reset to synced" only appears for an already-edited match, and '
    'clears the flag on tap',
    (tester) async {
      final edited = match(rp: 55, editedFields: {'rp_change'});
      final store = _FakeStore([edited]);
      RankedMatch? result;

      await tester.pumpWidget(
        app(
          match: edited,
          store: store,
          prefs: await emptyPrefs(),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reset to synced'), findsOneWidget);

      await tester.tap(find.text('Reset to synced'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.editedFields, isEmpty);
      final stored = store.rows[edited.dedupKey]!;
      expect(stored.editedFields, isEmpty);
      // clearEdits only resets the flag - the corrected value itself is left
      // as-is until the next sync overwrites it.
      expect(stored.rpChange, 55);
    },
  );

  testWidgets('no edited fields yet: "Reset to synced" is absent', (
    tester,
  ) async {
    final m = match();
    final store = _FakeStore([m]);

    await tester.pumpWidget(
      app(match: m, store: store, prefs: await emptyPrefs(), onResult: (_) {}),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Reset to synced'), findsNothing);
  });

  testWidgets(
    'saving invalidates the providers the rest of the breakdown reads from',
    (tester) async {
      final m = match();
      final store = _FakeStore([m]);
      final prefs = await emptyPrefs();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          rankedHistoryStoreProvider.overrideWithValue(store),
          rankedSyncProvider(
            uid,
          ).overrideWith((ref) async => RankedSyncOutcome.synced),
        ],
      );
      addTearDown(container.dispose);

      const arg = (uid: uid, splitId: kUnknownSplitId);
      // Held for the whole test so rankedSplitMatchesProvider doesn't
      // naturally tear itself down (autoDispose) between the two reads
      // below - only invalidateMatchDerivedProviders actually calling
      // ref.invalidate should be what makes the second read fresh.
      container.listen(rankedSplitMatchesProvider(arg), (_, _) {});

      final before = await container.read(
        rankedSplitMatchesProvider(arg).future,
      );
      expect(before.single.rpChange, m.rpChange);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showMatchEditSheet(context, m),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '55');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final after = await container.read(
        rankedSplitMatchesProvider(arg).future,
      );
      expect(after.single.rpChange, 55);
    },
  );
}
