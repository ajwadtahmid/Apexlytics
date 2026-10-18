import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import '../../constants/map_constants.dart';
import '../../models/seasonal_maps.dart';
import '../../providers/map_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/map_alert_actions.dart';
import '../../utils/notifications.dart';
import '../../utils/theme.dart';
import '../../widgets/error_card.dart';
import '../../widgets/setting_row.dart';
import 'widgets/map_mode_list.dart';
import 'widgets/notification_health_banners.dart';
import '../../widgets/sheet_handle.dart';

void showMapAlertsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _MapAlertsSheetContent(),
  );
}

class _MapAlertsSheetContent extends ConsumerStatefulWidget {
  const _MapAlertsSheetContent();

  @override
  ConsumerState<_MapAlertsSheetContent> createState() =>
      _MapAlertsSheetContentState();
}

class _MapAlertsSheetContentState
    extends ConsumerState<_MapAlertsSheetContent> {
  late Set<String> _rankedNotify;
  late Set<String> _pubsNotify;
  bool _showAllRanked = false;
  bool _showAllPubs = false;
  bool _sendingTest = false;
  _TestAlertNote? _testNote;

  // Whether _initializeFromSettings() last saw real map names. "Empty
  // favorites" means "notify every map" and seeds from the current name
  // list — but if the sheet opens before seasonalMaps resolves, that list is
  // itself empty, so every map renders unchecked instead of all-checked.
  // Lets the listener below re-seed once real names arrive.
  bool _namesInitialized = false;
  ProviderSubscription<AsyncValue<SeasonalMaps>>? _seasonalMapsSub;

  static const _battleRoyaleOptions = [0, 5, 15, 30];
  static const _otherModesOptions = [0, 5, 10, 15];

  @override
  void initState() {
    super.initState();
    _initializeFromSettings();
    _seasonalMapsSub = ref.listenManual(seasonalMapsProvider, (prev, next) {
      if (!_namesInitialized && next.asData?.value != null) {
        setState(_initializeFromSettings);
      }
    });
  }

  @override
  void dispose() {
    _seasonalMapsSub?.close();
    super.dispose();
  }

  void _initializeFromSettings() {
    final settings = ref.read(playerSettingsProvider);
    final seasonalMaps = ref.read(seasonalMapsProvider).asData?.value;

    final rankedNames = seasonalMaps?.ranked.map((m) => m.name).toList() ?? [];
    final pubsNames = seasonalMaps?.pubs.map((m) => m.name).toList() ?? [];
    _namesInitialized = rankedNames.isNotEmpty || pubsNames.isNotEmpty;

    _rankedNotify = settings.favoriteRankedMapNames.isEmpty
        ? Set.from(rankedNames)
        : Set.from(settings.favoriteRankedMapNames);
    _pubsNotify = settings.favoritePubsMapNames.isEmpty
        ? Set.from(pubsNames)
        : Set.from(settings.favoritePubsMapNames);
  }

  // Visible map names for a mode:
  // 1. Proxy maps in proxy order (always shown)
  // 2. Non-proxy maps in kBattleRoyaleMaps order — shown if selected OR expanded.
  //    kBattleRoyaleMaps order is the canonical order, so toggling a map never
  //    moves it while the sheet is open. On next open, selected extras appear
  //    without expanding because they pass the _notify check.
  List<String> _visibleNames(
    List<AppMap> proxyMaps,
    Set<String> notifySet,
    bool showAll,
  ) {
    // An empty proxy list means the backend hasn't been updated for the
    // season yet — fall back to showing the full canonical map list instead
    // of hiding everything behind the expand tile.
    final effectiveShowAll = showAll || proxyMaps.isEmpty;
    final proxyNames = proxyMaps.map((m) => m.name).toSet();
    final result = [...proxyMaps.map((m) => m.name)];
    for (final m in kBattleRoyaleMaps.values) {
      if (proxyNames.contains(m.name)) continue;
      if (effectiveShowAll || _has(notifySet, m.name)) result.add(m.name);
    }
    return result;
  }

  // Spelling-insensitive, like the alert planner.
  static bool _has(Set<String> names, String name) {
    final key = mapNameKey(name);
    return names.any((n) => mapNameKey(n) == key);
  }

  // Number of non-proxy, unselected maps still hidden behind the expand tile.
  int _hiddenCount(
    List<AppMap> proxyMaps,
    Set<String> notifySet,
    bool showAll,
  ) {
    if (showAll || proxyMaps.isEmpty) return 0;
    final proxyNames = proxyMaps.map((m) => m.name).toSet();
    return kBattleRoyaleMaps.values
        .where((m) => !proxyNames.contains(m.name) && !_has(notifySet, m.name))
        .length;
  }

  String _timingLabel(int minutes) => switch (minutes) {
    0 => 'Off',
    _ => '$minutes min before',
  };

  Future<void> _pickTiming(BuildContext context, MapAlertMode mode) async {
    final settings = ref.read(playerSettingsProvider);
    final current = switch (mode) {
      MapAlertMode.ranked => settings.rankedNotifyMinutesBefore,
      MapAlertMode.pubs => settings.pubsNotifyMinutesBefore,
      MapAlertMode.wildcard => settings.wildcardNotifyMinutesBefore,
      MapAlertMode.mixtape => settings.mixtapeNotifyMinutesBefore,
    };

    final options = switch (mode) {
      MapAlertMode.ranked || MapAlertMode.pubs => _battleRoyaleOptions,
      MapAlertMode.wildcard || MapAlertMode.mixtape => _otherModesOptions,
    };

    final currentIndex = options.indexOf(current);
    final effectiveIndex = currentIndex < 0 ? 0 : currentIndex;

    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Alert timing'),
        children: options.asMap().entries.map((entry) {
          final i = entry.key;
          final minutes = entry.value;
          final selected = i == effectiveIndex;
          return SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              if (minutes > 0 && current == 0) {
                await NotificationService.requestPermissions();
              }
              final notifier = ref.read(playerSettingsProvider.notifier);
              switch (mode) {
                case MapAlertMode.ranked:
                  await notifier.setRankedNotifyMinutesBefore(minutes);
                case MapAlertMode.pubs:
                  await notifier.setPubsNotifyMinutesBefore(minutes);
                case MapAlertMode.wildcard:
                  await notifier.setWildcardNotifyMinutesBefore(minutes);
                case MapAlertMode.mixtape:
                  await notifier.setMixtapeNotifyMinutesBefore(minutes);
              }
              await _reschedule();
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _timingLabel(minutes),
                    style: TextStyle(
                      color: selected ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check, color: AppTheme.accent, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _toggleMode(
    BuildContext context,
    MapAlertMode mode,
    bool enabled,
  ) async {
    final previouslyEnabled = ref
        .read(playerSettingsProvider)
        .alertEnabled(mode);

    if (enabled && !previouslyEnabled) {
      await turnOnMapAlert(context, ref, mode);
      return;
    }

    final notifier = ref.read(playerSettingsProvider.notifier);
    switch (mode) {
      case MapAlertMode.pubs:
        await notifier.setNotifyPubsMapRotation(enabled);
      case MapAlertMode.ranked:
        await notifier.setNotifyRankedMapRotation(enabled);
      case MapAlertMode.wildcard:
        await notifier.setNotifyWildcardMapRotation(enabled);
      case MapAlertMode.mixtape:
        await notifier.setNotifyMixtapeMapRotation(enabled);
    }

    if (!enabled) await _cancelIfAllOff();
  }

  Future<void> _cancelIfAllOff() async {
    if (!ref.read(playerSettingsProvider).anyMapAlertActive) {
      await NotificationService.cancelAll();
    }
  }

  Future<void> _toggleMap(
    MapAlertMode mode,
    String modeLabel,
    String mapName,
    Set<String> notifySet,
    Set<String> allNames,
    Future<void> Function(List<String>) save,
  ) async {
    // Unticking the last map turns the mode off: an empty favourites list means
    // "every map". Favourites reset to all, so re-enabling shows every map ticked.
    if (notifySet.length == 1 && _has(notifySet, mapName)) {
      setState(() {
        notifySet
          ..clear()
          ..addAll(allNames);
      });
      await save(const <String>[]);
      if (!mounted) return;
      await _toggleMode(context, mode, false);
      if (!mounted) return;
      context.showMessage(
        '$modeLabel alerts are off: no maps were left selected.',
      );
      return;
    }
    setState(
      () => _has(notifySet, mapName)
          ? notifySet.removeWhere((n) => mapNameKey(n) == mapNameKey(mapName))
          : notifySet.add(mapName),
    );
    final toSave =
        notifySet.containsAll(allNames) && allNames.containsAll(notifySet)
        ? <String>[]
        : notifySet.toList();
    await save(toSave);
    await _reschedule();
  }

  Future<void> _toggleRanked(String mapName) async {
    final allNames =
        ref
            .read(seasonalMapsProvider)
            .asData
            ?.value
            .ranked
            .map((m) => m.name)
            .toSet() ??
        {};
    await _toggleMap(
      MapAlertMode.ranked,
      'Ranked',
      mapName,
      _rankedNotify,
      allNames,
      (list) => ref
          .read(playerSettingsProvider.notifier)
          .setFavoriteRankedMapNames(list),
    );
  }

  Future<void> _togglePubs(String mapName) async {
    final allNames =
        ref
            .read(seasonalMapsProvider)
            .asData
            ?.value
            .pubs
            .map((m) => m.name)
            .toSet() ??
        {};
    await _toggleMap(
      MapAlertMode.pubs,
      'Pubs',
      mapName,
      _pubsNotify,
      allNames,
      (list) => ref
          .read(playerSettingsProvider.notifier)
          .setFavoritePubsMapNames(list),
    );
  }

  Future<void> _reschedule() => rescheduleMapAlerts(ref);

  Future<void> _sendTestAlert() async {
    setState(() {
      _sendingTest = true;
      _testNote = null;
    });
    final result = await ref.read(testAlertSenderProvider)();
    if (!mounted) return;
    setState(() {
      _sendingTest = false;
      _testNote = _TestAlertNote.of(result, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifyRanked = ref.watch(
      playerSettingsProvider.select((s) => s.notifyRankedMapRotation),
    );
    final rankedMinutesBefore = ref.watch(
      playerSettingsProvider.select((s) => s.rankedNotifyMinutesBefore),
    );
    final notifyPubs = ref.watch(
      playerSettingsProvider.select((s) => s.notifyPubsMapRotation),
    );
    final pubsMinutesBefore = ref.watch(
      playerSettingsProvider.select((s) => s.pubsNotifyMinutesBefore),
    );
    final notifyWildcard = ref.watch(
      playerSettingsProvider.select((s) => s.notifyWildcardMapRotation),
    );
    final wildcardMinutesBefore = ref.watch(
      playerSettingsProvider.select((s) => s.wildcardNotifyMinutesBefore),
    );
    final notifyMixtape = ref.watch(
      playerSettingsProvider.select((s) => s.notifyMixtapeMapRotation),
    );
    final mixtapeMinutesBefore = ref.watch(
      playerSettingsProvider.select((s) => s.mixtapeNotifyMinutesBefore),
    );
    final seasonalMapsAsync = ref.watch(seasonalMapsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => seasonalMapsAsync.when(
        data: (seasonalMaps) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.md,
            AppTheme.md,
            AppTheme.md,
            AppTheme.lg,
          ),
          children: [
            const SheetHandle(),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Map Rotation Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.xs),
            const Text(
              'Tap a mode to enable or disable it. '
              'Green maps fire an alert; red maps are skipped.',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppTheme.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _sendingTest ? null : _sendTestAlert,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Send a test alert'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
              ),
            ),
            if (_testNote case final note?)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.sm),
                child: InkWell(
                  onTap: note.opensSettings ? openAppSettings : null,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(note.icon, size: 18, color: note.color),
                      const SizedBox(width: AppTheme.sm),
                      Expanded(
                        child: Text(
                          note.text,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                      if (note.opensSettings)
                        const Text(
                          'Fix',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppTheme.sm),

            SettingsCard(
              child: Column(
                children: [
                  // Here too, not just the Settings card: this is where
                  // alerts get switched on.
                  NotificationHealthBanners(
                    alertsActive:
                        (notifyRanked && rankedMinutesBefore > 0) ||
                        (notifyPubs && pubsMinutesBefore > 0) ||
                        (notifyWildcard && wildcardMinutesBefore > 0) ||
                        (notifyMixtape && mixtapeMinutesBefore > 0),
                    separator: const Divider(
                      color: AppTheme.surface2,
                      height: 24,
                    ),
                  ),
                  // ── Ranked ─────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.leaderboard_outlined,
                    label: 'Ranked',
                    enabled: notifyRanked,
                    onTap: () => _toggleMode(
                      context,
                      MapAlertMode.ranked,
                      !notifyRanked,
                    ),
                  ),
                  if (notifyRanked) ...[
                    MapTimingTile(
                      label: _timingLabel(rankedMinutesBefore),
                      onTap: () => _pickTiming(context, MapAlertMode.ranked),
                    ),
                    ..._visibleNames(
                      seasonalMaps.ranked,
                      _rankedNotify,
                      _showAllRanked,
                    ).map(
                      (name) => MapAlertTile(
                        name: name,
                        notify: _has(_rankedNotify, name),
                        onTap: () => _toggleRanked(name),
                      ),
                    ),
                    if (_hiddenCount(
                          seasonalMaps.ranked,
                          _rankedNotify,
                          _showAllRanked,
                        ) >
                        0)
                      MapExpandTile(
                        count: _hiddenCount(
                          seasonalMaps.ranked,
                          _rankedNotify,
                          _showAllRanked,
                        ),
                        onTap: () => setState(() => _showAllRanked = true),
                      ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Pubs ───────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.public,
                    label: 'Pubs',
                    enabled: notifyPubs,
                    onTap: () =>
                        _toggleMode(context, MapAlertMode.pubs, !notifyPubs),
                  ),
                  if (notifyPubs) ...[
                    MapTimingTile(
                      label: _timingLabel(pubsMinutesBefore),
                      onTap: () => _pickTiming(context, MapAlertMode.pubs),
                    ),
                    ..._visibleNames(
                      seasonalMaps.pubs,
                      _pubsNotify,
                      _showAllPubs,
                    ).map(
                      (name) => MapAlertTile(
                        name: name,
                        notify: _has(_pubsNotify, name),
                        onTap: () => _togglePubs(name),
                      ),
                    ),
                    if (_hiddenCount(
                          seasonalMaps.pubs,
                          _pubsNotify,
                          _showAllPubs,
                        ) >
                        0)
                      MapExpandTile(
                        count: _hiddenCount(
                          seasonalMaps.pubs,
                          _pubsNotify,
                          _showAllPubs,
                        ),
                        onTap: () => setState(() => _showAllPubs = true),
                      ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Wildcards ───────────────────────────────────────
                  MapModeTile(
                    icon: Icons.casino,
                    label: 'Wildcards',
                    enabled: notifyWildcard,
                    onTap: () => _toggleMode(
                      context,
                      MapAlertMode.wildcard,
                      !notifyWildcard,
                    ),
                  ),
                  if (notifyWildcard) ...[
                    MapTimingTile(
                      label: _timingLabel(wildcardMinutesBefore),
                      onTap: () => _pickTiming(context, MapAlertMode.wildcard),
                    ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Mixtape ─────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.music_note_outlined,
                    label: 'Mixtape',
                    enabled: notifyMixtape,
                    onTap: () => _toggleMode(
                      context,
                      MapAlertMode.mixtape,
                      !notifyMixtape,
                    ),
                  ),
                  if (notifyMixtape) ...[
                    MapTimingTile(
                      label: _timingLabel(mixtapeMinutesBefore),
                      onTap: () => _pickTiming(context, MapAlertMode.mixtape),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorCard(
          fullScreen: true,
          message: friendlyError(err),
          onRetry: () => ref.invalidate(seasonalMapsProvider),
        ),
      ),
    );
  }
}

/// What the sheet says under "Send a test alert" once one has been tried.
class _TestAlertNote {
  final IconData icon;
  final Color color;
  final String text;

  /// Whether tapping it should open the system's notification settings.
  final bool opensSettings;

  const _TestAlertNote(
    this.icon,
    this.color,
    this.text, {
    this.opensSettings = false,
  });

  /// [at] is when it was tried, so a second try visibly changes the note.
  static _TestAlertNote of(
    TestAlertResult result,
    DateTime at,
  ) => switch (result) {
    TestAlertResult.sent => _TestAlertNote(
      Icons.check_circle_outline,
      AppTheme.green,
      'Sent at ${DateFormat('h:mm a').format(at)}. If it did not show, check '
      'your notification settings or battery limits for Apexlytics.',
    ),
    TestAlertResult.permissionOff => const _TestAlertNote(
      Icons.notifications_off_outlined,
      AppTheme.red,
      'Notifications are off for Apexlytics.',
      opensSettings: true,
    ),
    TestAlertResult.notReady => const _TestAlertNote(
      Icons.error_outline,
      AppTheme.red,
      "Alerts couldn't start. Try restarting the app.",
    ),
    TestAlertResult.failed => const _TestAlertNote(
      Icons.error_outline,
      AppTheme.red,
      "Couldn't send the test alert. Try again.",
    ),
  };
}
