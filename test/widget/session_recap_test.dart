import 'package:apexlytics/screens/ranked/ranked_sessions_screen.dart';
import 'package:apexlytics/utils/ranked/ranked_aggregates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RankedSession session({required int killsGames}) => RankedSession(
    start: DateTime(2026, 9, 1, 20),
    end: DateTime(2026, 9, 1, 21),
    games: 3,
    netRp: 20,
    totalKills: killsGames * 2,
    totalDamage: 0,
    killsGames: killsGames,
    damageGames: 0,
    matches: const [],
  );

  Future<void> pump(WidgetTester tester, RankedSession s) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SessionRecapBody(session: s)),
    ),
  );

  testWidgets('kills show no reading when no game reported them', (
    tester,
  ) async {
    await pump(tester, session(killsGames: 0));

    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('kills show the total when some games reported them', (
    tester,
  ) async {
    await pump(tester, session(killsGames: 2));

    expect(find.text('4'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });
}
