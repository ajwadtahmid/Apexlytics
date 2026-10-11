import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexlytics/utils/navigation_utils.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');

  /// Pumps a button that opens a link, with the plugin answering as
  /// [onLaunch] says (a bool, or throwing).
  Future<void> pumpAndTap(
    WidgetTester tester,
    Future<Object?> Function() onLaunch,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) => onLaunch(),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openExternalLink(context, Uri.parse('mailto:a@b.test')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('says so when the platform throws, as Android does with no app '
      'to handle the link', (tester) async {
    await pumpAndTap(
      tester,
      () async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('says so when the platform reports failure', (tester) async {
    await pumpAndTap(tester, () async => false);

    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('says nothing when the link opened', (tester) async {
    await pumpAndTap(tester, () async => true);

    expect(find.text('Could not open link'), findsNothing);
  });
}
