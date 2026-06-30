import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'widgets/map_rotation_card.dart';
import 'widgets/predator_section.dart';
import 'widgets/summary_tile_skeleton.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  ProviderSubscription? _mapSub;
  ProviderSubscription? _settingsSub;
  Timer? _rotationRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapSub = ref.listenManual(mapRotationProvider, (_, next) {
      switch (next) {
        case AsyncData<ApiResult<MapRotation>>(:final value):
          MapNotificationService.schedule(ref, value.data);
          _scheduleRotationRefresh(value.data);
        case AsyncError():
          // A refetch failed (map rotation uses noCache, so errors don't fall
          // back to cache). Re-arm a short retry so the rescheduling loop heals
          // itself instead of dying permanently on a transient network blip.
          _rotationRefreshTimer?.cancel();
          _rotationRefreshTimer = Timer(
            const Duration(minutes: 1),
            () => ref.invalidate(mapRotationProvider),
          );
        default:
          break;
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The foreground refresh timer is frozen while the app is backgrounded,
      // so refetch on resume to top up the notification queue immediately.
      ref.invalidate(mapRotationProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                data: (result) => MapRotationCard(
                  rotation: result.data,
                  onExpired: () => ref.invalidate(mapRotationProvider),
                ),
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
