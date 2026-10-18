import 'package:apexlytics/constants/ui_strings.dart';
import 'package:apexlytics/utils/lookup_form_state.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/lookup_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LookupFormState state;
  var submits = 0;

  Future<void> pump(
    WidgetTester t, {
    LookupFormState? with_,
    bool arrowSubmits = false,
    String? error,
  }) async {
    submits = 0;
    state = with_ ?? LookupFormState();
    addTearDown(state.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LookupCard(
              state: state,
              onSubmit: () => submits++,
              arrowSubmits: arrowSubmits,
              error: error,
            ),
          ),
        ),
      ),
    );
  }

  Finder platform(String label) => find.text(label);

  /// Whether the segment labelled [label], of either capsule, is the filled one.
  bool segmentSelected(WidgetTester t, String label) {
    final box = t.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return (box.decoration as BoxDecoration).color == AppTheme.accent;
  }

  bool platformSelected(WidgetTester t, String label) =>
      segmentSelected(t, label);

  Finder hint() => find.textContaining('Know their UID?', findRichText: true);

  group('the Name | UID capsule', () {
    testWidgets('shows both options, with the one in use filled', (t) async {
      await pump(t);

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('UID'), findsOneWidget);
      expect(segmentSelected(t, 'Name'), isTrue);
      expect(segmentSelected(t, 'UID'), isFalse);
      expect(find.text('Player name'), findsOneWidget);
    });

    testWidgets('choosing UID fills it instead, and changes the field', (
      t,
    ) async {
      await pump(t);

      await t.tap(find.text('UID'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(state.byUid, isTrue);
      expect(segmentSelected(t, 'UID'), isTrue);
      expect(segmentSelected(t, 'Name'), isFalse);
      expect(find.text('Numeric UID'), findsOneWidget);

      await t.tap(find.text('Name'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(state.byUid, isFalse);
      expect(segmentSelected(t, 'Name'), isTrue);
    });

    testWidgets('has no lock, until Switch makes UID the only way', (t) async {
      await pump(t);
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      await t.tap(platform('Switch'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(segmentSelected(t, 'UID'), isTrue);
      expect(find.text(switchAutoUidNotice), findsOneWidget);
    });

    testWidgets('on Switch, choosing Name explains why it cannot be', (
      t,
    ) async {
      await pump(t);
      await t.tap(platform('Switch'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      await t.tap(find.text('Name'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(segmentSelected(t, 'UID'), isTrue);
      expect(find.text(switchNeedsUidWarning), findsOneWidget);
      expect(find.text(switchAutoUidNotice), findsNothing);
    });

    testWidgets(
      'is a smaller capsule of the platforms\' look, above the field',
      (t) async {
        await pump(t);

        Finder track(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == AppTheme.surface2 &&
                (w.decoration! as BoxDecoration).borderRadius ==
                    BorderRadius.circular(AppTheme.radiusFull),
          ),
        );
        final modes = t.getSize(track('Name'));
        final platforms = t.getSize(track('PC'));
        // Quieter than the platform choice: shorter, and only as wide as its two
        // options, in the middle.
        expect(modes.height, lessThan(platforms.height - 8));
        expect(modes.width, lessThan(platforms.width / 2));
        expect(
          t.getCenter(track('Name')).dx,
          closeTo(t.getCenter(track('PC')).dx, 0.5),
        );
        expect(
          t.getTopLeft(track('Name')).dy,
          lessThan(t.getTopLeft(find.byType(TextField)).dy),
        );
        expect(
          t.getTopLeft(find.byType(TextField)).dy,
          lessThan(t.getTopLeft(track('PC')).dy),
        );
      },
    );

    testWidgets('each option is announced as a selectable button', (t) async {
      await pump(t);
      final handle = t.ensureSemantics();

      final uid = find.bySemanticsLabel('Search by UID');
      expect(
        t.getSemantics(uid),
        matchesSemantics(
          label: 'Search by UID',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('Search by name')),
        matchesSemantics(
          label: 'Search by name',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('the line under the field', () {
    testWidgets('says the UID way exists while searching by name', (t) async {
      await pump(t);

      expect(hint(), findsOneWidget);
      expect(find.text('Find your UID'), findsNothing);
    });

    testWidgets('a tap on it switches to UID', (t) async {
      await pump(t);

      await t.tap(hint());
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(state.byUid, isTrue);
      expect(hint(), findsNothing);
    });

    testWidgets('gives way to where to find a UID, once searching by one', (
      t,
    ) async {
      await pump(t);

      await t.tap(find.text('UID'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Find your UID'), findsOneWidget);
      expect(hint(), findsNothing);
    });

    testWidgets('where to find a UID is marked as a link out of the app', (
      t,
    ) async {
      await pump(t);
      expect(find.byIcon(Icons.open_in_new), findsNothing);

      await t.tap(find.text('UID'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      final link = find.ancestor(
        of: find.text('Find your UID'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: link, matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget,
      );
    });

    testWidgets('gives way to the stronger suggestion for digits', (t) async {
      await pump(t);

      await t.enterText(find.byType(TextField), '1000000000001');
      await t.pump();

      expect(hint(), findsNothing);
      expect(
        find.text('Looks like a UID. Tap to search by UID.'),
        findsOneWidget,
      );

      await t.enterText(find.byType(TextField), 'Aceu');
      await t.pump();

      expect(hint(), findsOneWidget);
    });
  });

  group('the platform pills', () {
    testWidgets('are PC, PS, Xbox and Switch, in a row', (t) async {
      await pump(t);

      final dx = [
        for (final p in ['PC', 'PS', 'Xbox', 'Switch'])
          t.getTopLeft(platform(p)).dx,
      ];
      expect(dx, [...dx]..sort());
      final dy = {
        for (final p in ['PC', 'PS', 'Xbox', 'Switch'])
          t.getTopLeft(platform(p)).dy.round(),
      };
      expect(dy, hasLength(1));
    });

    testWidgets('share one rounded track, as the Home mode picker does', (
      t,
    ) async {
      await pump(t);

      Finder track(String label) => find.ancestor(
        of: platform(label),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == AppTheme.surface2 &&
              (w.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(AppTheme.radiusFull),
        ),
      );
      final tracks = {
        for (final p in ['PC', 'PS', 'Xbox', 'Switch'])
          track(p).evaluate().single.widget,
      };
      expect(tracks, hasLength(1));
      // The one not selected has no fill of its own.
      final idle = t.widget<AnimatedContainer>(
        find.ancestor(
          of: platform('Xbox'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((idle.decoration! as BoxDecoration).color, Colors.transparent);
    });

    testWidgets('light up the one selected', (t) async {
      await pump(t);
      expect(platformSelected(t, 'PC'), isTrue);
      expect(platformSelected(t, 'Xbox'), isFalse);

      await t.tap(platform('Xbox'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(state.platform, 'X1');
      expect(platformSelected(t, 'Xbox'), isTrue);
      expect(platformSelected(t, 'PC'), isFalse);
    });
  });

  group('the rest of the card', () {
    testWidgets('suggests UID for digits typed as a name', (t) async {
      await pump(t);

      await t.enterText(find.byType(TextField), '1000000000001');
      await t.pump();

      expect(find.text('Looks like a UID. Tap to search by UID.'), findsOne);
      await t.tap(find.text('Looks like a UID. Tap to search by UID.'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));

      expect(state.byUid, isTrue);
    });

    testWidgets('has an arrow that submits only when asked for', (t) async {
      await pump(t);
      expect(find.byIcon(Icons.arrow_forward), findsNothing);

      await pump(t, arrowSubmits: true);
      await t.tap(find.byIcon(Icons.arrow_forward));

      expect(submits, 1);
    });

    testWidgets('submits from the keyboard', (t) async {
      await pump(t);

      await t.enterText(find.byType(TextField), 'Aceu');
      await t.testTextInput.receiveAction(TextInputAction.done);

      expect(submits, 1);
    });

    testWidgets('shows a notice, and drops it when typing starts', (t) async {
      await pump(t);
      state.showNotice('Heads up');
      await t.pump();
      expect(find.text('Heads up'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'A');
      await t.pump();

      expect(find.text('Heads up'), findsNothing);
    });

    testWidgets('shows an error from the caller', (t) async {
      await pump(t, error: 'Player not found.');

      expect(find.text('Player not found.'), findsOneWidget);
    });
  });
}
