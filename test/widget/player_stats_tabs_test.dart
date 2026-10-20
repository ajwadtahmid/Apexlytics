import 'package:apexlytics/constants/legend_constants.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/constants/stat_icons.dart';
import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/utils/theme.dart';
import 'package:apexlytics/widgets/control_pill.dart';
import 'package:apexlytics/widgets/legend_trackers_sheet.dart';
import 'package:apexlytics/widgets/legend_stats_section.dart';
import 'package:apexlytics/widgets/player_stats_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';

void main() {
  late SharedPreferences prefs;

  Future<void> pump(
    WidgetTester tester,
    List<LegendStat> legends, {
    Map<String, Object> saved = const {},
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlayerStatsTabs(legendStats: legends),
            ),
          ),
        ),
      ),
    );
  }

  LegendStat wraith(int kills) => buildLegend(
    name: 'Wraith',
    trackers: [buildTracker(key: 'kills', value: kills)],
  );

  LegendStat withKills(String name, int kills) => buildLegend(
    name: name,
    trackers: [
      buildTracker(key: 'kills', displayName: 'BR Kills', value: kills),
    ],
  );

  double top(WidgetTester tester, String name) =>
      tester.getTopLeft(find.text(name)).dy;

  // The text inside a pill: tapping the pill's own centre can land on its
  // "Sort:" or "Filter:" prefix instead.
  Finder pill(String label) => find.descendant(
    of: find.widgetWithText(ControlPill, label),
    matching: find.text(label),
  );

  final sortOption = find.descendant(
    of: find.byType(ListTile),
    matching: find.text('Kills'),
  );

  testWidgets('a refresh with the same legends shows the new tracker values', (
    tester,
  ) async {
    await pump(tester, [wraith(111)]);
    expect(find.text('111'), findsWidgets);

    // Pull-to-refresh rebuilds the same widget with fresh stats: same legend
    // name and order, new numbers.
    await pump(tester, [wraith(222)]);

    expect(find.text('222'), findsWidgets);
    expect(find.text('111'), findsNothing);
  });

  group('the trackers on each card', () {
    LegendStat bloodhound() => buildLegend(
      name: 'Bloodhound',
      trackers: [
        buildTracker(key: 'a', displayName: 'BR Kills', value: 15557),
        buildTracker(key: 'b', displayName: 'BR Executions', value: 310),
        buildTracker(key: 'c', displayName: 'BR Damage', value: 900000),
        buildTracker(key: 'd', displayName: 'Eye: Enemies scanned', value: 5),
        buildTracker(key: 'e', displayName: 'BR Season 1 Kills', value: 25),
        buildTracker(key: 'f', displayName: 'BR Season 3 Wins', value: 0),
      ],
    );

    testWidgets('are always kills and damage, as no reading when missing', (
      tester,
    ) async {
      await pump(tester, [buildLegend(name: 'Wraith', trackers: [])]);

      expect(find.text('BR Kills'), findsOneWidget);
      expect(find.text('BR Damage'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('start with kills on the top row and damage on the next', (
      tester,
    ) async {
      await pump(tester, [bloodhound()]);

      expect(top(tester, 'BR Kills'), lessThan(top(tester, 'BR Damage')));
      // The next trackers sit beside them, one to a row.
      expect(top(tester, 'BR Executions'), top(tester, 'BR Kills'));
      expect(top(tester, 'Eye: Enemies scanned'), top(tester, 'BR Damage'));
      expect(
        tester.getTopLeft(find.text('BR Executions')).dx,
        greaterThan(tester.getTopLeft(find.text('BR Kills')).dx),
      );
    });

    testWidgets('leave the rest for the legend\'s page, and say how many', (
      tester,
    ) async {
      await pump(tester, [bloodhound()]);

      expect(find.text('BR Season 1 Kills'), findsNothing);
      expect(find.text('BR Season 3 Wins'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
      // The chevron keeps its colour; the count is what says there is more.
      final chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
      expect(chevron.color, AppTheme.muted);
      expect(tester.widget<Text>(find.text('+2')).style?.color, AppTheme.muted);
    });

    testWidgets('give no count when everything fits', (tester) async {
      await pump(tester, [withKills('Wraith', 100)]);

      expect(find.textContaining('+'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('make every card the same height', (tester) async {
      await pump(tester, [
        buildLegend(name: 'Octane', trackers: []),
        withKills('Wraith', 100),
        bloodhound(),
        buildLegend(
          name: 'Lifeline',
          trackers: [
            buildTracker(
              key: 'a',
              displayName: 'Silence: Total damage while silenced',
              value: 2043,
            ),
          ],
        ),
        // Last, so the one before it is measured by where this one starts.
        withKills('Bangalore', 1),
      ]);

      final tops = [
        for (final n in [
          'Octane',
          'Wraith',
          'Bloodhound',
          'Lifeline',
          'Bangalore',
        ])
          top(tester, n),
      ];
      final gaps = [
        for (var i = 1; i < tops.length; i++) tops[i] - tops[i - 1],
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, 0.01), reason: '$gaps');
      }
    });

    testWidgets('are career kills, wins and revives on the career card', (
      tester,
    ) async {
      await pump(tester, [
        buildLegend(
          name: 'Global',
          trackers: [
            buildTracker(key: 'a', displayName: 'Career Kills', value: 500),
            buildTracker(key: 'b', displayName: 'Career Wins', value: 12),
          ],
        ),
      ]);

      expect(find.text('Career Kills'), findsOneWidget);
      expect(find.text('Career Wins'), findsOneWidget);
      expect(find.text('Career Revives'), findsOneWidget);
      expect(find.text('BR Kills'), findsNothing);
      // Revives isn't reported here.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('fit without scrolling sideways', (tester) async {
      await pump(tester, [bloodhound()]);

      expect(
        find.descendant(
          of: find.byType(LegendStatsSection),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final name in ['BR Kills', 'BR Executions', 'BR Damage']) {
        expect(tester.getRect(find.text(name)).right, lessThanOrEqualTo(width));
      }
    });
  });

  group('opening a legend', () {
    testWidgets('shows its trackers in a sheet', (tester) async {
      await pump(tester, [withKills('Wraith', 100)]);

      await tester.tap(find.text('Wraith'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(LegendTrackersSheet), findsOneWidget);
    });
  });

  group('what the numbers cover', () {
    testWidgets('says they are career totals, and when they last changed', (
      tester,
    ) async {
      await pump(tester, [
        LegendStat(
          name: 'Wraith',
          trackers: [buildTracker(key: 'kills', value: 5)],
          lastUpdated: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ]);

      expect(find.textContaining('Career totals'), findsOneWidget);
      expect(find.textContaining('Last changed 2h ago'), findsOneWidget);
    });

    testWidgets('leaves the time out when no legend has one', (tester) async {
      await pump(tester, [wraith(5)]);

      expect(find.textContaining('Career totals'), findsOneWidget);
      expect(find.textContaining('Last changed'), findsNothing);
    });

    testWidgets('is shown on the Guns tab too', (tester) async {
      await pump(tester, [wraith(5)]);

      await tester.tap(find.text('Guns'));
      await tester.pump();

      expect(find.textContaining('Career totals'), findsOneWidget);
    });
  });

  group('sorting the legends', () {
    testWidgets('a sheet lists every order, and choosing one applies it', (
      tester,
    ) async {
      await pump(tester, [
        withKills('Bangalore', 10),
        withKills('Wraith', 300),
      ]);
      expect(top(tester, 'Bangalore'), lessThan(top(tester, 'Wraith')));

      await tester.tap(pill('Recent'));
      await tester.pumpAndSettle();

      expect(find.text('Sort legends by'), findsOneWidget);
      for (final label in ['Recent', 'Kills', 'Damage', 'Wins', 'Role']) {
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }

      await tester.tap(sortOption);
      await tester.pumpAndSettle();

      expect(find.text('Sort legends by'), findsNothing);
      expect(top(tester, 'Wraith'), lessThan(top(tester, 'Bangalore')));
      expect(prefs.getString(PrefsKeys.legendSort), 'kills');
    });

    for (final (saved, icon) in [
      ('kills', StatIcons.totalKills),
      ('damage', StatIcons.totalDamage),
      ('wins', StatIcons.wins),
    ]) {
      testWidgets('the pill wears the $saved order\'s own icon, and its '
          'direction', (tester) async {
        await pump(
          tester,
          [withKills('Bangalore', 10), withKills('Wraith', 300)],
          saved: {PrefsKeys.legendSort: saved},
        );

        expect(find.byIcon(icon), findsOneWidget);
        expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
        // The order's icon leads the label; the direction is at the right.
        final pillLabel = find.descendant(
          of: find.byType(ControlPill),
          matching: find.text(saved[0].toUpperCase() + saved.substring(1)),
        );
        expect(
          tester.getTopLeft(find.byIcon(icon)).dx,
          lessThan(tester.getTopLeft(pillLabel).dx),
        );
        expect(
          tester.getTopLeft(find.byIcon(Icons.arrow_downward)).dx,
          greaterThan(tester.getTopLeft(pillLabel).dx),
        );
      });
    }

    testWidgets('choosing the order in use turns it round', (tester) async {
      await pump(
        tester,
        [withKills('Bangalore', 10), withKills('Wraith', 300)],
        saved: {PrefsKeys.legendSort: 'kills'},
      );
      expect(top(tester, 'Wraith'), lessThan(top(tester, 'Bangalore')));
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      await tester.tap(pill('Kills'));
      await tester.pumpAndSettle();
      expect(find.text('Highest first'), findsOneWidget);
      await tester.tap(sortOption);
      await tester.pumpAndSettle();

      expect(top(tester, 'Bangalore'), lessThan(top(tester, 'Wraith')));
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(prefs.getBool(PrefsKeys.legendSortReversed), isTrue);

      await tester.tap(pill('Kills'));
      await tester.pumpAndSettle();
      expect(find.text('Lowest first'), findsOneWidget);
    });

    testWidgets('comes back the way it was left', (tester) async {
      await pump(
        tester,
        [withKills('Bangalore', 10), withKills('Wraith', 300)],
        saved: {
          PrefsKeys.legendSort: 'kills',
          PrefsKeys.legendSortReversed: true,
        },
      );

      expect(top(tester, 'Bangalore'), lessThan(top(tester, 'Wraith')));
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });
  });

  group('the role filter', () {
    testWidgets('is a button beside sort, not a row of chips', (tester) async {
      await pump(tester, [
        withKills('Bangalore', 10),
        withKills('Wraith', 300),
      ]);

      expect(find.text('Filter:'), findsOneWidget);
      expect(find.text('Sort:'), findsOneWidget);
      expect(pill('All'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      // Filter at the left edge, sort at the right.
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getRect(find.text('Filter:')).left, lessThan(48));
      expect(tester.getRect(pill('Recent')).right, greaterThan(width - 48));
    });

    testWidgets('has its own glyph in the button while on All', (tester) async {
      await pump(tester, [withKills('Bangalore', 10)]);

      final all = find.widgetWithText(ControlPill, 'All');
      expect(
        find.descendant(of: all, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: all, matching: find.byIcon(Icons.apps)),
        findsOneWidget,
      );
    });

    testWidgets('is tinted orange on All, as a role is in its own colour', (
      tester,
    ) async {
      await pump(tester, [withKills('Bangalore', 10)]);

      final box = tester.widget<Container>(
        find.ancestor(of: pill('All'), matching: find.byType(Container)).first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        AppTheme.accent.withAlpha(35),
      );
      expect(tester.widget<Text>(pill('All')).style?.color, AppTheme.accent);
    });

    testWidgets(
      'turns the whole button the role\'s colour once one is chosen',
      (tester) async {
        await pump(
          tester,
          [withKills('Bangalore', 10)],
          saved: {PrefsKeys.legendRoleFilter: 'skirmisher'},
        );

        final color = LegendRole.skirmisher.color;
        final box = tester.widget<Container>(
          find
              .ancestor(
                of: pill('Skirmisher'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((box.decoration as BoxDecoration).color, color.withAlpha(35));
        expect(tester.widget<Text>(pill('Skirmisher')).style?.color, color);
      },
    );

    testWidgets(
      'shows the role\'s own badge in the button once one is chosen',
      (tester) async {
        await pump(
          tester,
          [withKills('Bangalore', 10)],
          saved: {PrefsKeys.legendRoleFilter: 'assault'},
        );

        final chosen = find.widgetWithText(ControlPill, 'Assault');
        expect(
          find.descendant(of: chosen, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: chosen, matching: find.byIcon(Icons.apps)),
          findsNothing,
        );
      },
    );

    testWidgets('lists every role, with the one in use lit, All included', (
      tester,
    ) async {
      await pump(tester, [withKills('Bangalore', 10)]);

      await tester.tap(pill('All'));
      await tester.pumpAndSettle();

      expect(find.text('Filter legends by role'), findsOneWidget);
      for (final label in [
        'All',
        'Assault',
        'Skirmisher',
        'Recon',
        'Support',
        'Controller',
      ]) {
        expect(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      Color? colorOf(String label) => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(ListTile),
              matching: find.text(label),
            ),
          )
          .style
          ?.color;
      expect(colorOf('All'), AppTheme.accent);
      expect(colorOf('Assault'), isNot(AppTheme.accent));
    });

    testWidgets(
      'keeps All\'s glyph orange even when it is not the one chosen',
      (tester) async {
        await pump(
          tester,
          [withKills('Bangalore', 10)],
          saved: {PrefsKeys.legendRoleFilter: 'assault'},
        );

        await tester.tap(pill('Assault'));
        await tester.pumpAndSettle();

        final glyph = tester.widget<Icon>(
          find.descendant(
            of: find.byType(ListTile),
            matching: find.byIcon(Icons.apps),
          ),
        );
        expect(
          IconTheme.of(tester.element(find.byWidget(glyph))).color,
          AppTheme.accent,
        );
      },
    );

    testWidgets('narrows the list and is kept when chosen', (tester) async {
      await pump(tester, [
        withKills('Bangalore', 10),
        withKills('Wraith', 300),
      ]);

      await tester.tap(pill('All'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Assault'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filter legends by role'), findsNothing);
      expect(find.text('Wraith'), findsNothing);
      expect(find.text('Bangalore'), findsOneWidget);
      expect(find.widgetWithText(ControlPill, 'Assault'), findsOneWidget);
      expect(prefs.getString(PrefsKeys.legendRoleFilter), 'assault');
    });

    testWidgets('choosing All again brings every legend back', (tester) async {
      await pump(
        tester,
        [withKills('Bangalore', 10), withKills('Wraith', 300)],
        saved: {PrefsKeys.legendRoleFilter: 'assault'},
      );

      await tester.tap(pill('Assault'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(ListTile), matching: find.text('All')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wraith'), findsOneWidget);
      expect(find.text('Bangalore'), findsOneWidget);
      expect(prefs.containsKey(PrefsKeys.legendRoleFilter), isFalse);
    });

    testWidgets('comes back as it was left', (tester) async {
      await pump(
        tester,
        [withKills('Bangalore', 10), withKills('Wraith', 300)],
        saved: {PrefsKeys.legendRoleFilter: 'skirmisher'},
      );

      expect(find.text('Bangalore'), findsNothing);
      expect(find.text('Wraith'), findsOneWidget);
      expect(find.widgetWithText(ControlPill, 'Skirmisher'), findsOneWidget);
    });
  });
}
