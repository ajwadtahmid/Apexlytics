import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/map_constants.dart';
import '../../providers/map_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/background_service.dart';
import '../../services/notification_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/theme.dart';
import '../../widgets/setting_row.dart';
import 'widgets/map_mode_list.dart';

void showMapAlertsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppTheme.radiusLg),
      ),
    ),
    builder: (_) => const _MapAlertsSheetContent(),
  );
}

enum _NotifMode { pubs, ranked, wildcard, mixtape }

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

  static const _notifyOptions = [0, 5, 10, 15];
  static const _kDefaultNotifyMinutes = 10;

  @override
  void initState() {
    super.initState();
    _initializeFromSettings();
  }

  void _initializeFromSettings() {
    final settings = ref.read(playerSettingsProvider);
    final seasonalMaps = ref.read(seasonalMapsProvider).asData?.value;

    final rankedNames = seasonalMaps?.ranked.map((m) => m.name).toList() ?? [];
    final pubsNames = seasonalMaps?.pubs.map((m) => m.name).toList() ?? [];

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
    final proxyNames = proxyMaps.map((m) => m.name).toSet();
    final result = [...proxyMaps.map((m) => m.name)];
    for (final m in kBattleRoyaleMaps) {
      if (proxyNames.contains(m.name)) continue;
      if (showAll || notifySet.contains(m.name)) result.add(m.name);
    }
    return result;
  }

  // Number of non-proxy, unselected maps still hidden behind the expand tile.
  int _hiddenCount(List<AppMap> proxyMaps, Set<String> notifySet, bool showAll) {
    if (showAll) return 0;
    final proxyNames = proxyMaps.map((m) => m.name).toSet();
    return kBattleRoyaleMaps
        .where((m) => !proxyNames.contains(m.name) && !notifySet.contains(m.name))
        .length;
  }

  String _timingLabel(int minutes) => switch (minutes) {
    0 => 'Off',
    _ => '$minutes min before',
  };

  Future<void> _pickTiming(BuildContext context, _NotifMode mode) async {
    final settings = ref.read(playerSettingsProvider);
    final current = switch (mode) {
      _NotifMode.ranked => settings.rankedNotifyMinutesBefore,
      _NotifMode.pubs => settings.pubsNotifyMinutesBefore,
      _NotifMode.wildcard => settings.wildcardNotifyMinutesBefore,
      _NotifMode.mixtape => settings.mixtapeNotifyMinutesBefore,
    };
    final currentIndex = _notifyOptions.indexOf(current);
    final effectiveIndex = currentIndex < 0 ? 0 : currentIndex;

    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Alert timing'),
        children: _notifyOptions.asMap().entries.map((entry) {
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
                case _NotifMode.ranked:
                  await notifier.setRankedNotifyMinutesBefore(minutes);
                case _NotifMode.pubs:
                  await notifier.setPubsNotifyMinutesBefore(minutes);
                case _NotifMode.wildcard:
                  await notifier.setWildcardNotifyMinutesBefore(minutes);
                case _NotifMode.mixtape:
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
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (selected) const Icon(Icons.check, color: AppTheme.accent, size: 18),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _toggleMode(
    BuildContext context,
    _NotifMode mode,
    bool enabled,
  ) async {
    final settings = ref.read(playerSettingsProvider);
    final previouslyEnabled = switch (mode) {
      _NotifMode.ranked => settings.notifyRankedMapRotation,
      _NotifMode.pubs => settings.notifyPubsMapRotation,
      _NotifMode.wildcard => settings.notifyWildcardMapRotation,
      _NotifMode.mixtape => settings.notifyMixtapeMapRotation,
    };

    final notifier = ref.read(playerSettingsProvider.notifier);
    switch (mode) {
      case _NotifMode.pubs:
        await notifier.setNotifyPubsMapRotation(enabled);
      case _NotifMode.ranked:
        await notifier.setNotifyRankedMapRotation(enabled);
      case _NotifMode.wildcard:
        await notifier.setNotifyWildcardMapRotation(enabled);
      case _NotifMode.mixtape:
        await notifier.setNotifyMixtapeMapRotation(enabled);
    }

    if (enabled && !previouslyEnabled) {
      await NotificationService.requestPermissions();
      if (!context.mounted) return;
      // Set a default timing if none is configured for this mode.
      final s = ref.read(playerSettingsProvider);
      final currentTiming = switch (mode) {
        _NotifMode.ranked => s.rankedNotifyMinutesBefore,
        _NotifMode.pubs => s.pubsNotifyMinutesBefore,
        _NotifMode.wildcard => s.wildcardNotifyMinutesBefore,
        _NotifMode.mixtape => s.mixtapeNotifyMinutesBefore,
      };
      if (currentTiming == 0) {
        switch (mode) {
          case _NotifMode.ranked:
            await notifier.setRankedNotifyMinutesBefore(_kDefaultNotifyMinutes);
          case _NotifMode.pubs:
            await notifier.setPubsNotifyMinutesBefore(_kDefaultNotifyMinutes);
          case _NotifMode.wildcard:
            await notifier.setWildcardNotifyMinutesBefore(_kDefaultNotifyMinutes);
          case _NotifMode.mixtape:
            await notifier.setMixtapeNotifyMinutesBefore(_kDefaultNotifyMinutes);
        }
      }
      await _reschedule();
      if (!context.mounted) return;
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        final available = await BackgroundService.isAvailable();
        if (!available && context.mounted) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.surface,
              title: const Text('Background Refresh Disabled'),
              content: const Text(
                'Notifications will only fire while the app is open.\n\n'
                'To get alerts when the app is closed, enable Background App '
                'Refresh in:\niOS Settings → General → Background App Refresh '
                '→ Apexlytics',
                style: TextStyle(color: AppTheme.muted, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: AppTheme.accent)),
                ),
              ],
            ),
          );
        }
      }
    } else {
      await _cancelIfAllOff(disabledMode: mode);
    }
  }

  Future<void> _cancelIfAllOff({required _NotifMode disabledMode}) async {
    final s = ref.read(playerSettingsProvider);
    final anyEnabled =
        (disabledMode != _NotifMode.pubs && s.notifyPubsMapRotation) ||
        (disabledMode != _NotifMode.ranked && s.notifyRankedMapRotation) ||
        (disabledMode != _NotifMode.wildcard && s.notifyWildcardMapRotation) ||
        (disabledMode != _NotifMode.mixtape && s.notifyMixtapeMapRotation);
    if (!anyEnabled) await NotificationService.cancelAll();
  }

  Future<void> _toggleMap(
    String mapName,
    Set<String> notifySet,
    Set<String> allNames,
    Future<void> Function(List<String>) save,
  ) async {
    setState(() => notifySet.contains(mapName)
        ? notifySet.remove(mapName)
        : notifySet.add(mapName));
    final toSave =
        notifySet.containsAll(allNames) && allNames.containsAll(notifySet)
            ? <String>[]
            : notifySet.toList();
    await save(toSave);
    await _reschedule();
  }

  Future<void> _toggleRanked(String mapName) async {
    final allNames =
        ref.read(seasonalMapsProvider).asData?.value.ranked
            .map((m) => m.name)
            .toSet() ??
        {};
    await _toggleMap(
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
        ref.read(seasonalMapsProvider).asData?.value.pubs
            .map((m) => m.name)
            .toSet() ??
        {};
    await _toggleMap(
      mapName,
      _pubsNotify,
      allNames,
      (list) => ref
          .read(playerSettingsProvider.notifier)
          .setFavoritePubsMapNames(list),
    );
  }

  Future<void> _reschedule() async {
    try {
      final result = await ref.read(mapRotationProvider.future);
      final s = ref.read(playerSettingsProvider);
      await NotificationService.scheduleAll(
        result.data,
        notifyRanked: s.notifyRankedMapRotation,
        rankedMinutesBefore: s.rankedNotifyMinutesBefore,
        notifyPubs: s.notifyPubsMapRotation,
        pubsMinutesBefore: s.pubsNotifyMinutesBefore,
        notifyWildcard: s.notifyWildcardMapRotation,
        wildcardMinutesBefore: s.wildcardNotifyMinutesBefore,
        notifyMixtape: s.notifyMixtapeMapRotation,
        mixtapeMinutesBefore: s.mixtapeNotifyMinutesBefore,
        favoriteRankedMapNames: s.favoriteRankedMapNames,
        favoritePubsMapNames: s.favoritePubsMapNames,
      );
    } catch (e) {
      log.w('Notification reschedule failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(playerSettingsProvider);
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
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.md),
            const Text(
              'Map Rotation Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppTheme.xs),
            const Text(
              'Tap a mode to enable or disable it. '
              'Green maps fire an alert; red maps are skipped.',
              style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: AppTheme.md),

            SettingsCard(
              child: Column(
                children: [
                  // ── Ranked ─────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.leaderboard_outlined,
                    label: 'Ranked',
                    enabled: settings.notifyRankedMapRotation,
                    onTap: () => _toggleMode(
                      context,
                      _NotifMode.ranked,
                      !settings.notifyRankedMapRotation,
                    ),
                  ),
                  if (settings.notifyRankedMapRotation) ...[
                    MapTimingTile(
                      label: _timingLabel(settings.rankedNotifyMinutesBefore),
                      onTap: () => _pickTiming(context, _NotifMode.ranked),
                    ),
                    ..._visibleNames(seasonalMaps.ranked, _rankedNotify, _showAllRanked)
                        .map((name) => MapAlertTile(
                          name: name,
                          notify: _rankedNotify.contains(name),
                          onTap: () => _toggleRanked(name),
                        )),
                    if (_hiddenCount(seasonalMaps.ranked, _rankedNotify, _showAllRanked) > 0)
                      MapExpandTile(
                        count: _hiddenCount(
                            seasonalMaps.ranked, _rankedNotify, _showAllRanked),
                        onTap: () => setState(() => _showAllRanked = true),
                      ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Pubs ───────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.public,
                    label: 'Pubs',
                    enabled: settings.notifyPubsMapRotation,
                    onTap: () => _toggleMode(
                      context,
                      _NotifMode.pubs,
                      !settings.notifyPubsMapRotation,
                    ),
                  ),
                  if (settings.notifyPubsMapRotation) ...[
                    MapTimingTile(
                      label: _timingLabel(settings.pubsNotifyMinutesBefore),
                      onTap: () => _pickTiming(context, _NotifMode.pubs),
                    ),
                    ..._visibleNames(seasonalMaps.pubs, _pubsNotify, _showAllPubs)
                        .map((name) => MapAlertTile(
                          name: name,
                          notify: _pubsNotify.contains(name),
                          onTap: () => _togglePubs(name),
                        )),
                    if (_hiddenCount(seasonalMaps.pubs, _pubsNotify, _showAllPubs) > 0)
                      MapExpandTile(
                        count: _hiddenCount(
                            seasonalMaps.pubs, _pubsNotify, _showAllPubs),
                        onTap: () => setState(() => _showAllPubs = true),
                      ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Wildcards ───────────────────────────────────────
                  MapModeTile(
                    icon: Icons.casino,
                    label: 'Wildcards',
                    enabled: settings.notifyWildcardMapRotation,
                    onTap: () => _toggleMode(
                      context,
                      _NotifMode.wildcard,
                      !settings.notifyWildcardMapRotation,
                    ),
                  ),
                  if (settings.notifyWildcardMapRotation) ...[
                    MapTimingTile(
                      label: _timingLabel(settings.wildcardNotifyMinutesBefore),
                      onTap: () => _pickTiming(context, _NotifMode.wildcard),
                    ),
                  ],

                  const Divider(color: AppTheme.surface2, height: 24),

                  // ── Mixtape ─────────────────────────────────────────
                  MapModeTile(
                    icon: Icons.music_note_outlined,
                    label: 'Mixtape',
                    enabled: settings.notifyMixtapeMapRotation,
                    onTap: () => _toggleMode(
                      context,
                      _NotifMode.mixtape,
                      !settings.notifyMixtapeMapRotation,
                    ),
                  ),
                  if (settings.notifyMixtapeMapRotation) ...[
                    MapTimingTile(
                      label: _timingLabel(settings.mixtapeNotifyMinutesBefore),
                      onTap: () => _pickTiming(context, _NotifMode.mixtape),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading maps: $err')),
      ),
    );
  }
}
