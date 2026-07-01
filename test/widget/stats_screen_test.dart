import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:apexlytics/models/player_stats.dart';
import 'package:apexlytics/providers/player_provider.dart';
import 'package:apexlytics/providers/settings_provider.dart';
import 'package:apexlytics/screens/stats/stats_screen.dart';
import 'package:apexlytics/services/api_service.dart' show ApiResult;
import 'package:apexlytics/widgets/stale_banner.dart';

import '../helpers.dart';

/// Fake notifier so the golden-path widget test can drive [StatsScreen] with a
/// fixed [ApiResult] instead of hitting the network. [softRefresh] is a no-op
/// so the stale-data auto-refresh path doesn't touch the real service.
class _FakeStatsNotifier extends MyPlayerStatsNotifier {
  _FakeStatsNotifier(this._result);
  final ApiResult<PlayerStats?> _result;

  @override
  Future<ApiResult<PlayerStats?>> build() async => _result;

  @override
  Future<void> softRefresh() async {}
}

Future<SharedPreferences> _prefsWithProfile() async {
  SharedPreferences.setMockInitialValues({
    'player_profiles': jsonEncode([
      {'name': 'TestPlayer', 'uid': 'uid123', 'platform': 'PC'},
    ]),
    'active_profile_index': 0,
  });
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs, {ApiResult<PlayerStats?>? result}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (result != null)
        myPlayerStatsProvider.overrideWith(() => _FakeStatsNotifier(result)),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: const StatsScreen(),
    ),
  );
}

void main() {
  testWidgets('shows player setup when no player is linked', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(_app(prefs));
    await tester.pump();

    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('renders the stats body (not skeleton) for fresh data', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _prefsWithProfile();

    await tester.pumpWidget(
      _app(prefs, result: ApiResult<PlayerStats?>(buildStats())),
    );
    await tester.pump();

    // Body rendered, not the loading skeleton or the setup view.
    expect(find.text('Get Started'), findsNothing);
    expect(find.byType(StaleBanner), findsNothing);
  });

  testWidgets('shows the stale banner when data is stale', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await _prefsWithProfile();
    final staleResult = ApiResult<PlayerStats?>(
      buildStats(),
      staleAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    await tester.pumpWidget(_app(prefs, result: staleResult));
    await tester.pump();

    expect(find.byType(StaleBanner), findsOneWidget);
    expect(find.textContaining('Last synced'), findsOneWidget);
  });
}
