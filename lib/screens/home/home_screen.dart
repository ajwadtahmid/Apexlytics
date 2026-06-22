import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/map_rotation.dart';
import '../../providers/map_provider.dart';
import '../../utils/api_cache.dart' show ApiResult;
import '../../providers/news_provider.dart';
import '../../providers/predator_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/background_service.dart';
import '../../services/map_notification_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatting/map_alerts_utils.dart';
import '../../utils/navigation_utils.dart';
import '../../utils/theme.dart';
import '../../widgets/widgets.dart';
import 'news_page.dart';
import 'server_status_page.dart';
import 'widgets/map_card_skeleton.dart';
import 'widgets/map_hero_image.dart';
import 'widgets/predator_section.dart';
import 'widgets/summary_tile_skeleton.dart';

const _kModeRanked = 'Ranked';
const _kModePubs = 'Pubs';
const _kModeWildcard = 'Wildcards';
const _kModeMixtape = 'Mixtape';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _modeIndex = 0;
  ProviderSubscription? _mapSub;
  ProviderSubscription? _settingsSub;
  Timer? _rotationRefreshTimer;

  @override
  void initState() {
    super.initState();
    _mapSub = ref.listenManual(mapRotationProvider, (_, next) {
      if (next case AsyncData<ApiResult<MapRotation>>(:final value)) {
        MapNotificationService.schedule(ref, value.data);
        _scheduleRotationRefresh(value.data);
      }
    });
    _settingsSub = ref.listenManual(playerSettingsProvider, (prev, next) {
      final p = prev as PlayerSettings?;
      final n = next as PlayerSettings;
      final changed =
          p?.notifyPubsMapRotation != n.notifyPubsMapRotation ||
          p?.notifyRankedMapRotation != n.notifyRankedMapRotation ||
          p?.notifyMixtapeMapRotation != n.notifyMixtapeMapRotation ||
          p?.notifyWildcardMapRotation != n.notifyWildcardMapRotation ||
          p?.rankedNotifyMinutesBefore != n.rankedNotifyMinutesBefore ||
          p?.pubsNotifyMinutesBefore != n.pubsNotifyMinutesBefore ||
          p?.mixtapeNotifyMinutesBefore != n.mixtapeNotifyMinutesBefore ||
          p?.wildcardNotifyMinutesBefore != n.wildcardNotifyMinutesBefore;
      if (!changed) return;
      // Sync background fetch cadence with the smallest active timing.
      BackgroundService.updateInterval(
        calculateMinActiveNotificationInterval(
          notifyRanked: n.notifyRankedMapRotation,
          rankedMinutes: n.rankedNotifyMinutesBefore,
          notifyPubs: n.notifyPubsMapRotation,
          pubsMinutes: n.pubsNotifyMinutesBefore,
          notifyMixtape: n.notifyMixtapeMapRotation,
          mixtapeMinutes: n.mixtapeNotifyMinutesBefore,
          notifyWildcard: n.notifyWildcardMapRotation,
          wildcardMinutes: n.wildcardNotifyMinutesBefore,
        ),
      );
      if (ref.read(mapRotationProvider) case AsyncData<ApiResult<MapRotation>>(:final value)) {
        MapNotificationService.schedule(ref, value.data);
      }
    });
  }

  /// Re-fetches map rotation data shortly after the soonest active rotation
  /// ends so notifications for the following rotation are scheduled promptly.
  void _scheduleRotationRefresh(MapRotation rotation) {
    _rotationRefreshTimer?.cancel();

    final s = ref.read(playerSettingsProvider);
    final anyNotif =
        (s.notifyRankedMapRotation && s.rankedNotifyMinutesBefore > 0) ||
        (s.notifyPubsMapRotation && s.pubsNotifyMinutesBefore > 0) ||
        (s.notifyMixtapeMapRotation && s.mixtapeNotifyMinutesBefore > 0) ||
        (s.notifyWildcardMapRotation && s.wildcardNotifyMinutesBefore > 0);
    if (!anyNotif) return;

    final candidates = <int>[
      if (s.notifyRankedMapRotation) rotation.rankedCurrent.remainingSecs,
      if (s.notifyPubsMapRotation) rotation.battleRoyaleCurrent.remainingSecs,
      if (s.notifyMixtapeMapRotation && rotation.ltmCurrent != null)
        rotation.ltmCurrent!.remainingSecs,
      if (s.notifyWildcardMapRotation && rotation.wildcardCurrent != null)
        rotation.wildcardCurrent!.remainingSecs,
    ];
    if (candidates.isEmpty) return;

    final soonestSecs = candidates.reduce((a, b) => a < b ? a : b);
    if (soonestSecs <= 0) {
      ref.invalidate(mapRotationProvider);
      return;
    }

    _rotationRefreshTimer = Timer(
      Duration(seconds: soonestSecs + 15),
      () => ref.invalidate(mapRotationProvider),
    );
  }

  @override
  void dispose() {
    _rotationRefreshTimer?.cancel();
    _mapSub?.close();
    _settingsSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerName = ref.watch(
      playerSettingsProvider.select((s) => s.name.isNotEmpty ? s.name : 'Guest'),
    );
    final mapAsync = ref.watch(mapRotationProvider);
    final serverAsync = ref.watch(serverStatusProvider);
    final newsAsync = ref.watch(newsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () async {
            ref.invalidate(mapRotationProvider);
            ref.invalidate(serverStatusProvider);
            ref.invalidate(newsProvider);
            ref.invalidate(predatorProvider);
            await Future.wait([
              ref
                  .read(mapRotationProvider.future)
                  .then((_) {}, onError: (e) => log.w('Map refresh failed', error: e)),
              ref
                  .read(serverStatusProvider.future)
                  .then((_) {}, onError: (e) => log.w('Server refresh failed', error: e)),
              ref
                  .read(newsProvider.future)
                  .then((_) {}, onError: (e) => log.w('News refresh failed', error: e)),
              ref
                  .read(predatorProvider.future)
                  .then((_) {}, onError: (e) => log.w('Predator refresh failed', error: e)),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.md,
              AppTheme.lg,
              AppTheme.md,
              AppTheme.lg,
            ),
            children: [
              // ── Header ──────────────────────────────────────────
              _Header(playerName: playerName),
              const SizedBox(height: AppTheme.xl),

              // ── Map rotation ─────────────────────────────────────
              mapAsync.when(
                data: (result) {
                  final modes = _buildModes(result.data);
                  if (modes.isEmpty) return const SizedBox.shrink();
                  final idx = _modeIndex.clamp(0, modes.length - 1);
                  return Column(
                    children: [
                      _ModePicker(
                        modes: modes.map((m) => m.label).toList(),
                        selected: idx,
                        onSelect: (i) => setState(() => _modeIndex = i),
                      ),
                      const SizedBox(height: AppTheme.md),
                      _MapCard(
                        mode: modes[idx],
                        onExpired: () => ref.invalidate(mapRotationProvider),
                      ),
                    ],
                  );
                },
                loading: () => const MapCardSkeleton(),
                error: (e, _) => ErrorCard(
                  message: friendlyError(e),
                  onRetry: () => ref.invalidate(mapRotationProvider),
                ),
              ),
              const SizedBox(height: AppTheme.md),

              // ── Predator cutoff ──────────────────────────────────
              const PredatorSection(),
              const SizedBox(height: AppTheme.sm),

              // ── News summary ─────────────────────────────────────
              newsAsync.when(
                data: (result) {
                  final articles = result.data;
                  final newsSubtitle = articles.isEmpty
                      ? 'No recent updates'
                      : articles.first.title.isNotEmpty
                      ? articles.first.title
                      : '${articles.length} article${articles.length == 1 ? "" : "s"}';
                  return SummaryCard(
                    leading: const Icon(
                      Icons.newspaper_outlined,
                      color: AppTheme.accent,
                      size: 22,
                    ),
                    title: 'Latest News',
                    subtitle: newsSubtitle,
                    onTap: () => context.pushPage(NewsPage(articles: result.data)),
                  );
                },
                loading: () => const SummaryTileSkeleton(),
                error: (e, _) => ErrorCard(
                  message: 'Latest News',
                  compact: true,
                  onRetry: () => ref.invalidate(newsProvider),
                ),
              ),
              const SizedBox(height: AppTheme.sm),

              // ── Server status summary ────────────────────────────
              serverAsync.when(
                data: (result) => ServerSummaryCard(
                  status: result.data,
                  onTap: () => context.pushPage(ServerStatusPage(status: result.data)),
                ),
                loading: () => const SummaryTileSkeleton(),
                error: (e, _) => ErrorCard(
                  message: 'Server Status',
                  compact: true,
                  onRetry: () => ref.invalidate(serverStatusProvider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_ModeData> _buildModes(MapRotation rotation) => [
    _ModeData(
      label: _kModeRanked,
      current: rotation.rankedCurrent,
      next: rotation.rankedNext,
    ),
    _ModeData(
      label: _kModePubs,
      current: rotation.battleRoyaleCurrent,
      next: rotation.battleRoyaleNext,
    ),
    if (rotation.wildcardCurrent != null && rotation.wildcardNext != null)
      _ModeData(
        label: _kModeWildcard,
        current: rotation.wildcardCurrent!,
        next: rotation.wildcardNext!,
      ),
    if (rotation.ltmCurrent != null && rotation.ltmNext != null)
      _ModeData(
        label: _kModeMixtape,
        current: rotation.ltmCurrent!,
        next: rotation.ltmNext!,
      ),
  ];
}

class _ModeData {
  final String label;
  final MapMode current;
  final MapMode next;
  const _ModeData({required this.label, required this.current, required this.next});
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String playerName;
  const _Header({required this.playerName});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'WELCOME',
          style: TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          playerName,
          style: const TextStyle(
            color: AppTheme.accent,
            fontSize: 34,
            fontWeight: FontWeight.bold,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

// ── Mode picker ───────────────────────────────────────────────────────────────

class _ModePicker extends StatelessWidget {
  final List<String> modes;
  final int selected;
  final ValueChanged<int> onSelect;

  const _ModePicker({
    required this.modes,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(4),
      radius: AppTheme.radiusFull,
      child: Row(
        children: List.generate(modes.length, (i) {
          final active = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: AppTheme.modePickerAnimationDuration,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? AppTheme.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  modes[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? Colors.white : AppTheme.muted,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Map card ──────────────────────────────────────────────────────────────────

const _kCountdownTickInterval = Duration(seconds: 1);

class _MapCard extends StatefulWidget {
  final _ModeData mode;
  final VoidCallback? onExpired;
  const _MapCard({required this.mode, this.onExpired});

  @override
  State<_MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<_MapCard> {
  late int _remaining;
  late DateTime _startedAt;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _reset(widget.mode.current.remainingSecs);
  }

  @override
  void didUpdateWidget(_MapCard old) {
    super.didUpdateWidget(old);
    if (old.mode.label != widget.mode.label ||
        old.mode.current.map != widget.mode.current.map ||
        old.mode.current.remainingSecs != widget.mode.current.remainingSecs) {
      _reset(widget.mode.current.remainingSecs);
    }
  }

  void _reset(int secs) {
    _expired = false;
    _timer?.cancel();
    _remaining = secs;
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_kCountdownTickInterval, (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_startedAt).inSeconds;
      final newRemaining = (secs - elapsed).clamp(0, secs);
      if (newRemaining != _remaining) {
        setState(() => _remaining = newRemaining);
      }
      if (newRemaining == 0 && !_expired) {
        _expired = true;
        _timer?.cancel();
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static final _endTimeFormat = DateFormat('h:mm a');

  static String _formatCountdown(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _formatEndTime(int remainingSecs) {
    final end = DateTime.now().add(Duration(seconds: remainingSecs));
    return _endTimeFormat.format(end);
  }

  static String _formatMapDisplay(String mapName, String? eventName, bool isMixtape) {
    if (isMixtape && eventName != null && eventName.isNotEmpty) {
      return '$mapName - $eventName';
    }
    return mapName;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.mode.current;
    final next = widget.mode.next;
    final isMixtape = widget.mode.label == _kModeMixtape;

    return SurfaceCard(
      radius: AppTheme.radiusLg,
      clip: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MapHeroImage(assetUrl: current.asset),
          Padding(
            padding: const EdgeInsets.all(AppTheme.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mode.label.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppTheme.xs),
                Text(
                  _formatMapDisplay(current.map, current.eventName, isMixtape),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppTheme.sm),
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: AppTheme.accent, size: 14),
                    const SizedBox(width: AppTheme.xs),
                    Text(
                      '${_formatCountdown(_remaining)} remaining',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(color: AppTheme.surface2, height: 1),
                const SizedBox(height: 10),
                _NextMapRow(
                  next: next,
                  remaining: _remaining,
                  isMixtape: isMixtape,
                  formatEndTime: _formatEndTime,
                  formatMapDisplay: _formatMapDisplay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Next map row ──────────────────────────────────────────────────────────────

class _NextMapRow extends StatelessWidget {
  final MapMode next;
  final int remaining;
  final bool isMixtape;
  final String Function(int) formatEndTime;
  final String Function(String, String?, bool) formatMapDisplay;

  const _NextMapRow({
    required this.next,
    required this.remaining,
    required this.isMixtape,
    required this.formatEndTime,
    required this.formatMapDisplay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'UP NEXT',
              style: TextStyle(
                color: AppTheme.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'Starts at ${formatEndTime(remaining)}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.xs),
        Row(
          children: [
            const Icon(Icons.arrow_forward, size: 14, color: AppTheme.muted),
            const SizedBox(width: AppTheme.xs),
            Expanded(
              child: Text(
                formatMapDisplay(next.map, next.eventName, isMixtape),
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
