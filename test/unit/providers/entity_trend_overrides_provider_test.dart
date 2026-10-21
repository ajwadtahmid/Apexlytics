import 'dart:convert';

import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/entity_trend_overrides_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('the keys', () {
    test('a legend is filed by its canonical name, whatever the case', () {
      expect(legendTrendKey('bloodhound'), legendTrendKey('Bloodhound'));
      expect(legendTrendKey('Wraith'), isNot(legendTrendKey('Octane')));
    });

    test('a map is filed by its canonical key, whatever the variant', () {
      expect(mapTrendKey('worlds_edge'), mapTrendKey('worlds_edge_rotation'));
    });

    test('a legend and a map never share one', () {
      expect(legendTrendKey('Olympus'), isNot(mapTrendKey('Olympus')));
    });
  });

  test('is empty until one is set', () async {
    final (container, _) = await prefsContainer();

    expect(container.read(entityTrendOverridesProvider), isEmpty);
  });

  test('comes back as it was saved', () async {
    final (container, _) = await prefsContainer(
      values: {
        PrefsKeys.entityTrendOverrides: jsonEncode({
          'legend:Octane': 25,
          'map:Olympus': 100,
        }),
      },
    );

    expect(container.read(entityTrendOverridesProvider), {
      'legend:Octane': 25,
      'map:Olympus': 100,
    });
  });

  test('Auto is a window of its own, besides the counts', () async {
    final (container, prefs) = await prefsContainer(
      values: {
        PrefsKeys.entityTrendOverrides: jsonEncode({'legend:Octane': 0}),
      },
    );
    expect(container.read(entityTrendOverridesProvider), {'legend:Octane': 0});

    await container
        .read(entityTrendOverridesProvider.notifier)
        .set('legend:Wraith', 0);

    expect(jsonDecode(prefs.getString(PrefsKeys.entityTrendOverrides)!), {
      'legend:Octane': 0,
      'legend:Wraith': 0,
    });
  });

  group('ignores what is damaged', () {
    for (final (name, saved) in [
      ('text that is not JSON', 'not json'),
      ('JSON that is not a map', '[1, 2, 3]'),
      ('a number out of range', '{"legend:Axle": 3}'),
      ('a value that is not a number', '{"legend:Axle": "ten"}'),
    ]) {
      test(name, () async {
        final (container, _) = await prefsContainer(
          values: {PrefsKeys.entityTrendOverrides: saved},
        );

        expect(container.read(entityTrendOverridesProvider), isEmpty);
      });
    }

    test('but keeps the good entries beside a bad one', () async {
      final (container, _) = await prefsContainer(
        values: {
          PrefsKeys.entityTrendOverrides: jsonEncode({
            'legend:Axle': 3,
            'legend:Octane': 50,
          }),
        },
      );

      expect(container.read(entityTrendOverridesProvider), {
        'legend:Octane': 50,
      });
    });
  });

  test('setting one changes only that one, and keeps it', () async {
    final (container, prefs) = await prefsContainer(
      values: {
        PrefsKeys.entityTrendOverrides: jsonEncode({'legend:Octane': 25}),
      },
    );

    await container
        .read(entityTrendOverridesProvider.notifier)
        .set('legend:Wraith', 10);

    expect(container.read(entityTrendOverridesProvider), {
      'legend:Octane': 25,
      'legend:Wraith': 10,
    });
    expect(jsonDecode(prefs.getString(PrefsKeys.entityTrendOverrides)!), {
      'legend:Octane': 25,
      'legend:Wraith': 10,
    });
  });

  test(
    'a count that is not a choice is ignored, in memory and on disk',
    () async {
      for (final bad in [-1, 1, 4, 1001, 50000]) {
        final (container, prefs) = await prefsContainer(
          values: {
            PrefsKeys.entityTrendOverrides: jsonEncode({'legend:Octane': 25}),
          },
        );

        await container
            .read(entityTrendOverridesProvider.notifier)
            .set('legend:Wraith', bad);

        expect(container.read(entityTrendOverridesProvider), {
          'legend:Octane': 25,
        }, reason: '$bad');
        expect(jsonDecode(prefs.getString(PrefsKeys.entityTrendOverrides)!), {
          'legend:Octane': 25,
        }, reason: '$bad');
      }
    },
  );

  test('setting one again replaces it', () async {
    final (container, _) = await prefsContainer();
    final notifier = container.read(entityTrendOverridesProvider.notifier);

    await notifier.set('legend:Octane', 10);
    await notifier.set('legend:Octane', 50);

    expect(container.read(entityTrendOverridesProvider), {'legend:Octane': 50});
  });

  test(
    'clearing one leaves the rest, and the last one empties the key',
    () async {
      final (container, prefs) = await prefsContainer(
        values: {
          PrefsKeys.entityTrendOverrides: jsonEncode({
            'legend:Octane': 25,
            'map:Olympus': 10,
          }),
        },
      );
      final notifier = container.read(entityTrendOverridesProvider.notifier);

      await notifier.clear('legend:Octane');
      expect(container.read(entityTrendOverridesProvider), {'map:Olympus': 10});
      expect(prefs.containsKey(PrefsKeys.entityTrendOverrides), isTrue);

      await notifier.clear('map:Olympus');
      expect(container.read(entityTrendOverridesProvider), isEmpty);
      expect(prefs.containsKey(PrefsKeys.entityTrendOverrides), isFalse);
    },
  );

  test('clearing one that was never set changes nothing', () async {
    final (container, _) = await prefsContainer(
      values: {
        PrefsKeys.entityTrendOverrides: jsonEncode({'legend:Octane': 25}),
      },
    );

    await container
        .read(entityTrendOverridesProvider.notifier)
        .clear('legend:Wraith');

    expect(container.read(entityTrendOverridesProvider), {'legend:Octane': 25});
  });
}
