import 'package:apexlytics/constants/legend_constants.dart';
import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/legend_list_options_provider.dart';
import 'package:apexlytics/utils/tracking/legend_stat_sort.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('starts on recent, the natural way round, with every role', () async {
    final (container, _) = await prefsContainer();

    final options = container.read(legendListOptionsProvider);

    expect(options.sort, LegendStatSort.recent);
    expect(options.reversed, isFalse);
    expect(options.role, isNull);
  });

  test('comes back as it was saved', () async {
    final (container, _) = await prefsContainer(
      values: {
        PrefsKeys.legendSort: 'wins',
        PrefsKeys.legendSortReversed: true,
        PrefsKeys.legendRoleFilter: 'support',
      },
    );

    final options = container.read(legendListOptionsProvider);

    expect(options.sort, LegendStatSort.wins);
    expect(options.reversed, isTrue);
    expect(options.role, LegendRole.support);
  });

  test('a sort that has been removed falls back to the default', () async {
    final (container, _) = await prefsContainer(
      values: {PrefsKeys.legendSort: 'winRate'},
    );

    expect(
      container.read(legendListOptionsProvider).sort,
      LegendStatSort.recent,
    );
  });

  test('a saved value it no longer knows falls back to the default', () async {
    final (container, _) = await prefsContainer(
      values: {
        PrefsKeys.legendSort: 'retired',
        PrefsKeys.legendRoleFilter: 'retired',
      },
    );

    final options = container.read(legendListOptionsProvider);

    expect(options.sort, LegendStatSort.recent);
    expect(options.role, isNull);
  });

  test('choosing a new order starts at its natural end', () async {
    final (container, prefs) = await prefsContainer(
      values: {
        PrefsKeys.legendSort: 'kills',
        PrefsKeys.legendSortReversed: true,
      },
    );

    await container
        .read(legendListOptionsProvider.notifier)
        .choose(LegendStatSort.wins);

    final options = container.read(legendListOptionsProvider);
    expect(options.sort, LegendStatSort.wins);
    expect(options.reversed, isFalse);
    expect(prefs.getString(PrefsKeys.legendSort), 'wins');
    expect(prefs.getBool(PrefsKeys.legendSortReversed), isFalse);
  });

  test('choosing the order in use turns it round, and again back', () async {
    final (container, prefs) = await prefsContainer();
    final notifier = container.read(legendListOptionsProvider.notifier);

    await notifier.choose(LegendStatSort.kills);
    await notifier.choose(LegendStatSort.kills);

    expect(container.read(legendListOptionsProvider).reversed, isTrue);
    expect(prefs.getBool(PrefsKeys.legendSortReversed), isTrue);

    await notifier.choose(LegendStatSort.kills);

    expect(container.read(legendListOptionsProvider).reversed, isFalse);
  });

  test('the role is kept, and clearing it forgets it', () async {
    final (container, prefs) = await prefsContainer();
    final notifier = container.read(legendListOptionsProvider.notifier);

    await notifier.setRole(LegendRole.recon);

    expect(container.read(legendListOptionsProvider).role, LegendRole.recon);
    expect(prefs.getString(PrefsKeys.legendRoleFilter), 'recon');

    await notifier.setRole(null);

    expect(container.read(legendListOptionsProvider).role, isNull);
    expect(prefs.containsKey(PrefsKeys.legendRoleFilter), isFalse);
  });
}
