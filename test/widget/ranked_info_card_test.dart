import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/models/predator.dart';
import 'package:apexlytics/providers/predator_provider.dart';
import 'package:apexlytics/services/api_service.dart';
import 'package:apexlytics/widgets/ranked_info_card.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int rp,
    required Map<String, dynamic> predator,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          predatorProvider.overrideWith(
            (ref) async => ApiResult(PredatorResponse.fromJson(predator)),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: RankedInfoCard(myRp: rp, platform: 'PC')),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a missing Predator cutoff does not make a Gold player Predator', (
    tester,
  ) async {
    // The platform entry is there but carries no `val`, which parses as 0.
    await pump(
      tester,
      rp: 5600,
      predator: {
        'RP': {'PC': <String, dynamic>{}},
      },
    );

    expect(find.text('Apex Predator'), findsNothing);
    expect(find.text('Gold IV'), findsOneWidget);
  });

  testWidgets('a real cutoff still promotes a player who reached it', (
    tester,
  ) async {
    await pump(
      tester,
      rp: 18000,
      predator: {
        'RP': {
          'PC': {'val': 17500, 'totalMastersAndPreds': 900},
        },
      },
    );

    expect(find.text('Apex Predator'), findsOneWidget);
  });

  testWidgets('a Master below the cutoff stays Master', (tester) async {
    await pump(
      tester,
      rp: 17000,
      predator: {
        'RP': {
          'PC': {'val': 17500, 'totalMastersAndPreds': 900},
        },
      },
    );

    expect(find.text('Apex Predator'), findsNothing);
    expect(find.text('Master'), findsOneWidget);
  });
}
