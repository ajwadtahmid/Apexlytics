import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/models/predator.dart';
import 'package:apexlytics/providers/predator_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/ranked/widgets/ranked_summary_header.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:apexlytics/utils/ranked/ranked_period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const summary = RankedSummary(
    games: 3,
    netRp: 120,
    currentRp: 1500,
    latestRankImg: '',
    totalKills: 6,
    totalDamage: 1500,
    killsGames: 3,
    damageGames: 3,
    totalLengthSecs: 1800,
    wins: 2,
    losses: 1,
  );

  Future<void> pump(
    WidgetTester tester, {
    RankedSummary data = summary,
    int? live,
    RankedRpScope scope = const RankedRpScope(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          predatorProvider.overrideWith(
            (ref) async => ApiResult(PredatorResponse.fromJson(const {})),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RankedSummaryHeader(
                summary: data,
                uid: '1',
                splitId: 'br_ranked_s30_s2',
                livePlayerRp: live,
                rpScope: scope,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('today\'s RP is labelled current and flags an unsynced history', (
    tester,
  ) async {
    await pump(tester, live: 1600);

    expect(find.text('Current RP'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.text('No goal set'), findsOneWidget);
  });

  testWidgets('a past week names itself and shows no sync hint', (tester) async {
    await pump(
      tester,
      scope: const RankedRpScope(label: 'RP at end of Week 1', live: false),
    );

    expect(find.text('RP at end of Week 1'), findsOneWidget);
    expect(find.text('Current RP'), findsNothing);
    expect(find.byIcon(Icons.sync), findsNothing);
    expect(find.text('1,500'), findsOneWidget);
  });

  testWidgets('a previous season drops the goal footer', (tester) async {
    await pump(
      tester,
      scope: const RankedRpScope(
        label: 'RP at end of Season 28 (Split 2)',
        live: false,
        showGoal: false,
      ),
    );

    expect(find.text('RP at end of Season 28 (Split 2)'), findsOneWidget);
    expect(find.text('No goal set'), findsNothing);
  });

  testWidgets('a past week with no games still shows where the player stood', (
    tester,
  ) async {
    const empty = RankedSummary(
      games: 0,
      netRp: 0,
      currentRp: 1500,
      latestRankImg: '',
      totalKills: 0,
      totalDamage: 0,
      killsGames: 0,
      damageGames: 0,
      totalLengthSecs: 0,
      wins: 0,
      losses: 0,
    );
    await pump(
      tester,
      data: empty,
      live: 1600,
      scope: const RankedRpScope(label: 'RP at end of Week 3', live: false),
    );

    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('1,600'), findsNothing);
  });

  testWidgets('a week before the first game shows a dash, not the live RP', (
    tester,
  ) async {
    await pump(
      tester,
      data: RankedSummary.empty,
      live: 1600,
      scope: const RankedRpScope(
        label: 'RP at end of Week 1',
        live: false,
        hasRp: false,
      ),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.text('1,600'), findsNothing);
  });
}
