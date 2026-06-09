import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apexlytics/utils/storage/legend_stack_storage.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loadLegendStack', () {
    test('returns empty list when nothing stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await loadLegendStack(prefs), isEmpty);
    });

    test('returns empty list on corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({'legend_visit_stack': 'not-json'});
      final prefs = await SharedPreferences.getInstance();
      expect(await loadLegendStack(prefs), isEmpty);
    });
  });

  group('pushToLegendStack', () {
    test('throws ArgumentError for empty name', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(() => pushToLegendStack('', prefs), throwsArgumentError);
    });

    test('prepends legend to empty stack', () async {
      final prefs = await SharedPreferences.getInstance();
      final result = await pushToLegendStack('Wraith', prefs);
      expect(result, ['Wraith']);
    });

    test('prepends legend to existing stack', () async {
      final prefs = await SharedPreferences.getInstance();
      await pushToLegendStack('Wraith', prefs);
      final result = await pushToLegendStack('Bangalore', prefs);
      expect(result.first, 'Bangalore');
      expect(result, contains('Wraith'));
    });

    test('is a no-op when legend already at index 0', () async {
      final prefs = await SharedPreferences.getInstance();
      await pushToLegendStack('Wraith', prefs);
      final result = await pushToLegendStack('Wraith', prefs);
      expect(result, ['Wraith']);
    });

    test('moves legend to front when it exists elsewhere in stack', () async {
      final prefs = await SharedPreferences.getInstance();
      await pushToLegendStack('Wraith', prefs);
      await pushToLegendStack('Bangalore', prefs);
      await pushToLegendStack('Lifeline', prefs);
      // Wraith is now at index 2; pushing it should move to front
      final result = await pushToLegendStack('Wraith', prefs);
      expect(result.first, 'Wraith');
      expect(result.where((e) => e == 'Wraith').length, 1);
    });

    test('removes all duplicates when stack is corrupted with repeats', () async {
      // Simulate corrupted state with duplicates in prefs — Wraith NOT at index 0
      // so the early-return guard does not fire before removeWhere runs.
      SharedPreferences.setMockInitialValues({
        'legend_visit_stack': '["Bangalore","Wraith","Wraith"]',
      });
      final prefs = await SharedPreferences.getInstance();
      final result = await pushToLegendStack('Wraith', prefs);
      expect(result.where((e) => e == 'Wraith').length, 1);
      expect(result.first, 'Wraith');
    });

    test('persists across separate prefs reads', () async {
      final prefs = await SharedPreferences.getInstance();
      await pushToLegendStack('Fuse', prefs);
      final reloaded = await loadLegendStack(prefs);
      expect(reloaded, contains('Fuse'));
    });
  });
}
