import 'package:apexlytics/constants/prefs_keys.dart';
import 'package:apexlytics/providers/pick_rate_options_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('starts with the minimum on and 0 RP as the line', () async {
    final (container, _) = await prefsContainer();

    final options = container.read(pickRateOptionsProvider);

    expect(options.showAll, isFalse);
    expect(options.useOwnAverage, isFalse);
    expect(options.tableView, isFalse);
  });

  test('comes back as it was saved', () async {
    final (container, _) = await prefsContainer(
      values: {
        PrefsKeys.pickRateShowAll: true,
        PrefsKeys.pickRateOwnAverage: true,
        PrefsKeys.pickRateTable: true,
      },
    );

    final options = container.read(pickRateOptionsProvider);

    expect(options.showAll, isTrue);
    expect(options.useOwnAverage, isTrue);
    expect(options.tableView, isTrue);
  });

  test('each choice changes on its own and is kept', () async {
    final (container, prefs) = await prefsContainer();
    final notifier = container.read(pickRateOptionsProvider.notifier);

    await notifier.setShowAll(true);

    expect(container.read(pickRateOptionsProvider).showAll, isTrue);
    expect(container.read(pickRateOptionsProvider).useOwnAverage, isFalse);
    expect(prefs.getBool(PrefsKeys.pickRateShowAll), isTrue);

    await notifier.setUseOwnAverage(true);

    expect(container.read(pickRateOptionsProvider).showAll, isTrue);
    expect(container.read(pickRateOptionsProvider).useOwnAverage, isTrue);
    expect(prefs.getBool(PrefsKeys.pickRateOwnAverage), isTrue);

    await notifier.setTableView(true);

    expect(container.read(pickRateOptionsProvider).tableView, isTrue);
    expect(container.read(pickRateOptionsProvider).showAll, isTrue);
    expect(prefs.getBool(PrefsKeys.pickRateTable), isTrue);
  });
}
